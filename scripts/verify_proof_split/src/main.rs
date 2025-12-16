use clap::{Parser, Subcommand};
use ethers::{
    contract::ContractError,
    core::k256::ecdsa::SigningKey,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{LocalWallet, Signer, Wallet},
    types::{Address, U256, U64},
    utils::hex,
};
use stark_evm_adapter::{
    annotated_proof::AnnotatedProof,
    annotation_parser::split_fri_merkle_statements,
    oods_statement::FactTopology,
    ContractFunctionCall,
};
use std::{convert::TryFrom, env, fs::read_to_string, str::FromStr, sync::Arc};

#[derive(Parser, Debug)]
#[command(name = "verify")]
#[command(about = "Verify large STARK proofs by splitting them into smaller transactions")]
struct Cli {
    #[command(subcommand)]
    network: Option<Network>,
    
    /// Path to annotated_proof.json file
    #[arg(short, long)]
    annotated_proof: Option<String>,
    
    /// Path to input.json file (for main proof verification)
    #[arg(short, long)]
    input_json: Option<String>,
    
    /// Path to fact_topologies.json file
    #[arg(short, long)]
    fact_topologies: Option<String>,
    
    /// RPC URL for Ethereum network (overrides network default and env vars)
    #[arg(short, long)]
    rpc_url: Option<String>,
}

#[derive(Subcommand, Debug)]
enum Network {
    /// Verify on Sepolia testnet
    Sepolia,
    /// Verify on Base Sepolia testnet
    BaseSepolia,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Note: Use direnv to load environment variables from .env
    // direnv will automatically load them into the shell, and env::var() will see them
    
    let cli = Cli::parse();
    
    // Load RPC URL - prioritize explicit --rpc-url, then network subcommand, then env vars
    let url = cli.rpc_url.or_else(|| {
        match &cli.network {
            Some(Network::Sepolia) => env::var("SEPOLIA_RPC_URL").ok(),
            Some(Network::BaseSepolia) => env::var("BASE_SEPOLIA_RPC_URL").ok(),
            None => env::var("SEPOLIA_RPC_URL").ok(),
        }
    }).expect("RPC URL must be set via --rpc-url, network subcommand (sepolia/base-sepolia), or SEPOLIA_RPC_URL env var");

    println!("Using RPC URL: {}", url);
    let provider: Provider<Http> = Provider::try_from(url.as_str())?;

    let private_key = env::var("PRIVATE_KEY")
        .expect("PRIVATE_KEY must be set in .env");
    let from_key_bytes = hex::decode(private_key.trim_start_matches("0x"))?;

    let from_signing_key = SigningKey::from_bytes(from_key_bytes.as_slice().into())?;
    let from_wallet: LocalWallet = LocalWallet::from(from_signing_key);
    println!("Wallet address: {:?}", from_wallet.address());

    let chain_id = provider.get_chainid().await?.as_u32();
    let signer: Arc<SignerMiddleware<_, _>> = Arc::new(SignerMiddleware::new(
        provider.clone(),
        from_wallet.with_chain_id(chain_id),
    ));

    // Load annotated proof - prioritize command line args, then env vars
    let annotated_proof_path = cli.annotated_proof
        .or_else(|| env::var("ANNOTATED_PROOF").ok())
        .expect("ANNOTATED_PROOF must be set in .env or use --annotated-proof <path>");
    
    println!("\n📄 Loading annotated proof:");
    println!("  Path: {}", annotated_proof_path);
    let origin_proof_file = read_to_string(&annotated_proof_path)?;
    let file_size = origin_proof_file.len();
    println!("  Size: {} bytes ({:.2} KB)", file_size, file_size as f64 / 1024.0);
    let annotated_proof: AnnotatedProof = serde_json::from_str(&origin_proof_file)?;
    println!("  ✅ Annotated proof loaded successfully");
    
    // Generate split proofs
    println!("Splitting proof into smaller parts...");
    let split_proofs = split_fri_merkle_statements(annotated_proof.clone())?;

    // Load fact topologies - prioritize command line args, then env vars
    let fact_topologies_path = cli.fact_topologies
        .or_else(|| env::var("FACT_TOPOLOGIES").ok())
        .expect("FACT_TOPOLOGIES must be set in .env or use --fact-topologies <path>");
    
    println!("\n📊 Loading fact topologies:");
    println!("  Path: {}", fact_topologies_path);
    let topologies_file = read_to_string(&fact_topologies_path)
        .map_err(|e| format!("Failed to read fact_topologies.json from {}: {}", fact_topologies_path, e))?;
    let file_size = topologies_file.len();
    println!("  Size: {} bytes ({:.2} KB)", file_size, file_size as f64 / 1024.0);
    let topology_json: serde_json::Value = serde_json::from_str(&topologies_file)?;
    let fact_topologies: Vec<FactTopology> = serde_json::from_value(topology_json.get("fact_topologies").unwrap().clone())?;
    println!("  Count: {} fact topologies", fact_topologies.len());
    println!("  ✅ Fact topologies loaded successfully");

    // Load contract addresses from deployment-addresses.json
    let deployment_json = read_to_string("deployment-addresses.json")
        .map_err(|e| format!("Failed to read deployment-addresses.json: {}. Current directory: {:?}", e, std::env::current_dir()))?;
    let deployment: serde_json::Value = serde_json::from_str(&deployment_json)?;
    
    // Use deployed addresses - no defaults to avoid confusion
    let merkle_statement_address = deployment.get("merkleStatementContract")
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .or_else(|| env::var("MERKLE_STATEMENT_ADDRESS").ok())
        .unwrap_or_else(|| {
            panic!("merkleStatementContract not found in deployment-addresses.json and MERKLE_STATEMENT_ADDRESS not set");
        });
    
    let fri_statement_address = deployment.get("friStatementContract")
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .or_else(|| env::var("FRI_STATEMENT_ADDRESS").ok())
        .unwrap_or_else(|| {
            panic!("friStatementContract not found in deployment-addresses.json and FRI_STATEMENT_ADDRESS not set");
        });
    
    let memory_registry_address = deployment.get("factRegistry")
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .or_else(|| env::var("MEMORY_REGISTRY_ADDRESS").ok())
        .unwrap_or_else(|| {
            panic!("factRegistry not found in deployment-addresses.json and MEMORY_REGISTRY_ADDRESS not set");
        });
    
    let gps_verifier_address = deployment.get("gpsVerifier")
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .or_else(|| env::var("GPS_VERIFIER_ADDRESS").ok())
        .unwrap_or_else(|| {
            panic!("gpsVerifier not found in deployment-addresses.json and GPS_VERIFIER_ADDRESS not set");
        });
    
    println!("Loaded contract addresses from deployment-addresses.json:");
    println!("  GPS Verifier: {}", gps_verifier_address);
    println!("  Merkle Statement Contract: {}", merkle_statement_address);
    println!("  FRI Statement Contract: {}", fri_statement_address);
    println!("  Memory Registry: {}", memory_registry_address);

    // Step 1: Verify trace decommitments
    println!("Verifying trace decommitments:");
    let merkle_contract_address = Address::from_str(&merkle_statement_address)?;
    for i in 0..split_proofs.merkle_statements.len() {
        let key = format!("Trace {}", i);
        let trace_merkle = split_proofs.merkle_statements.get(&key)
            .ok_or_else(|| format!("Trace {} not found", i))?;
        
        let call = trace_merkle.verify(merkle_contract_address, signer.clone());
        assert_call(call, &key).await?;
    }

    // Step 2: Verify FRI decommitments
    println!("Verifying FRI decommitments:");
    let fri_contract_address = Address::from_str(&fri_statement_address)?;
    for (i, fri_statement) in split_proofs.fri_merkle_statements.iter().enumerate() {
        let call = fri_statement.verify(fri_contract_address, signer.clone());
        assert_call(call, &format!("FRI statement: {}", i)).await?;
    }

    // Step 3: Register continuous pages
    let memory_fact_registry_address = Address::from_str(&memory_registry_address)?;
    let (_, continuous_pages) = split_proofs.main_proof.memory_page_registration_args();
    for (index, page) in continuous_pages.iter().enumerate() {
        let register_continuous_pages_call =
            split_proofs.main_proof.register_continuous_memory_page(
                memory_fact_registry_address,
                signer.clone(),
                page.clone(),
            );
        let name = format!("register continuous page: {}", index);
        assert_call(register_continuous_pages_call, &name).await?;
    }

    // Step 4: Verify main proof
    // Use input.json directly (like test Forge) instead of stark_evm_adapter
    // because stark_evm_adapter adds padding in memory_page_public_input which causes
    // "Invalid publicMemoryPages length" error
    println!("Verifying main proof:");
    let gps_verifier_addr = Address::from_str(&gps_verifier_address)?;
    
    // Load input.json for main proof verification - prioritize command line args, then env vars
    let input_json_path = cli.input_json
        .or_else(|| env::var("INPUT_JSON").ok())
        .expect("INPUT_JSON must be set in .env or use --input-json <path>");
    
    let input_json: serde_json::Value = serde_json::from_str(&read_to_string(&input_json_path)?)?;
    
    // Parse proof params, proof, public input, z, alpha, taskMetadata from input.json
    let proof_params_hex: Vec<String> = input_json.get("proof_params")
        .and_then(|v| v.as_array())
        .ok_or("proof_params not found in input.json")?
        .iter()
        .filter_map(|v| v.as_str().map(|s| s.to_string()))
        .collect();
    
    let proof_hex: Vec<String> = input_json.get("proof")
        .and_then(|v| v.as_array())
        .ok_or("proof not found in input.json")?
        .iter()
        .filter_map(|v| v.as_str().map(|s| s.to_string()))
        .collect();
    
    let public_input_hex: Vec<String> = input_json.get("public_input")
        .and_then(|v| v.as_array())
        .ok_or("public_input not found in input.json")?
        .iter()
        .filter_map(|v| v.as_str().map(|s| s.to_string()))
        .collect();
    
    let z_hex = input_json.get("z")
        .and_then(|v| v.as_str())
        .ok_or("z not found in input.json")?;
    let alpha_hex = input_json.get("alpha")
        .and_then(|v| v.as_str())
        .ok_or("alpha not found in input.json")?;
    
    let task_metadata_hex: Vec<String> = input_json.get("task_metadata")
        .and_then(|v| v.as_array())
        .ok_or("task_metadata not found in input.json")?
        .iter()
        .filter_map(|v| v.as_str().map(|s| s.to_string()))
        .collect();
    
    // Convert hex strings to U256
    let proof_params: Vec<U256> = proof_params_hex.iter()
        .map(|s| U256::from_str(s).map_err(|e| format!("Failed to parse proof_params hex '{}': {}", s, e)))
        .collect::<Result<Vec<_>, _>>()?;
    
    let proof: Vec<U256> = proof_hex.iter()
        .map(|s| U256::from_str(s).map_err(|e| format!("Failed to parse proof hex '{}': {}", s, e)))
        .collect::<Result<Vec<_>, _>>()?;
    
    let public_input: Vec<U256> = public_input_hex.iter()
        .map(|s| U256::from_str(s).map_err(|e| format!("Failed to parse public_input hex '{}': {}", s, e)))
        .collect::<Result<Vec<_>, _>>()?;
    
    let z = U256::from_str(z_hex)
        .map_err(|e| format!("Failed to parse z hex '{}': {}", z_hex, e))?;
    let alpha = U256::from_str(alpha_hex)
        .map_err(|e| format!("Failed to parse alpha hex '{}': {}", alpha_hex, e))?;
    
    let task_metadata: Vec<U256> = task_metadata_hex.iter()
        .map(|s| U256::from_str(s).map_err(|e| format!("Failed to parse task_metadata hex '{}': {}", s, e)))
        .collect::<Result<Vec<_>, _>>()?;
    
    // Create cairoAuxInput (public input + z + alpha) - same as test Forge
    let mut cairo_aux_input = public_input.clone();
    cairo_aux_input.push(z);
    cairo_aux_input.push(alpha);
    
    // Encode function call: verifyProofAndRegister(uint256[],uint256[],uint256[],uint256[],uint256)
    let function_selector = ethers::utils::keccak256(
        "verifyProofAndRegister(uint256[],uint256[],uint256[],uint256[],uint256)"
    )[..4].to_vec();
    let encoded = ethers::abi::encode(&[
        ethers::abi::Token::Array(proof_params.iter().map(|&v| ethers::abi::Token::Uint(v)).collect()),
        ethers::abi::Token::Array(proof.iter().map(|&v| ethers::abi::Token::Uint(v)).collect()),
        ethers::abi::Token::Array(task_metadata.iter().map(|&v| ethers::abi::Token::Uint(v)).collect()),
        ethers::abi::Token::Array(cairo_aux_input.iter().map(|&v| ethers::abi::Token::Uint(v)).collect()),
        ethers::abi::Token::Uint(U256::from(6u64)), // cairo_verifier_id = 6 (hardcoded in stark_evm_adapter)
    ]);
    
    let call_data = [&function_selector[..], &encoded[..]].concat();
    let tx = ethers::types::TransactionRequest::new()
        .to(gps_verifier_addr)
        .data(ethers::types::Bytes::from(call_data));
    
    let pending_tx = signer.send_transaction(tx, None).await?;
    println!("  Transaction sent, hash: {:?}", pending_tx.tx_hash());
    let receipt = pending_tx.await?.ok_or("Transaction receipt not found")?;
    match receipt.status {
        Some(status) if status == U64::from(1) => {
            println!("  ✅ Verified: Main proof");
        }
        Some(status) => {
            return Err(format!("Transaction failed with status {}: Main proof", status).into());
        }
        None => {
            return Err("Transaction status unknown: Main proof".into());
        }
    }

    println!("\n✅ All proof verification steps completed successfully!");
    Ok(())
}

async fn assert_call(
    call: ContractFunctionCall,
    name: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    match call.send().await {
        Ok(pending_tx) => match pending_tx.await {
            Ok(mined_tx) => {
                let tx_receipt = mined_tx.unwrap();
                if tx_receipt.status.unwrap_or_default() == U64::from(1) {
                    println!("Verified: {}", name);
                    Ok(())
                } else {
                    Err(format!("Transaction failed: {}, but did not revert.", name).into())
                }
            }
            Err(e) => Err(decode_revert_message(e.into()).into()),
        },
        Err(e) => {
            Err(decode_revert_message(e).into())
        }
    }
}

fn decode_revert_message(
    e: ContractError<SignerMiddleware<Provider<Http>, Wallet<SigningKey>>>,
) -> String {
    match e {
        ContractError::Revert(err) => {
            println!("Revert data: {:?}", err.0);
            err.to_string()
        }
        _ => format!("Transaction failed: {:?}", e),
    }
}

