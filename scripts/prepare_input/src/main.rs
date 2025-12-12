use num_bigint::BigInt;
use num_traits::{One, Zero};
use regex::Regex;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};
use std::collections::HashMap;
use std::env;
use std::fs;

/// Prime field constant for Cairo
const K_MODULUS_STR: &str = "0x800000000000011000000000000000000000000000000000000000000000001";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AnnotatedProof {
    annotations: Vec<String>,
    proof_hex: String,
    public_input: PublicInput,
    proof_parameters: ProofParameters,
}

/// Public memory for a cairo execution
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PublicMemory {
    pub address: u32,
    pub page: u32,
    // todo refactor to u256
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PublicInput {
    layout: String,
    memory_segments: HashMap<String, MemorySegment>,
    n_steps: u64,
    public_memory: Vec<PublicMemory>,
    rc_min: i64,
    rc_max: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemorySegment {
    begin_addr: u64,
    stop_ptr: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryCell {
    page: u64,
    #[serde(deserialize_with = "deserialize_address")]
    address: String,
    value: String,
}

fn deserialize_address<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde::Deserialize;
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Address {
        String(String),
        Number(u64),
    }

    match Address::deserialize(deserializer)? {
        Address::String(s) => Ok(s),
        Address::Number(n) => Ok(n.to_string()),
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ProofParameters {
    stark: StarkParams,
    #[serde(default)]
    n_verifier_friendly_commitment_layers: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StarkParams {
    log_n_cosets: u32,
    fri: FriParams,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FriParams {
    n_queries: u32,
    proof_of_work_bits: u32,
    last_layer_degree_bound: u32,
    fri_step_list: Vec<u32>,
}

#[derive(Debug, Serialize)]
struct MemoryPageRegular {
    #[serde(with = "hex_vec")]
    memory_pairs: Vec<BigInt>, // [addr0, value0, addr1, value1, ...]
}

#[derive(Debug, Serialize)]
struct MemoryPageContinuous {
    #[serde(with = "hex")]
    start_addr: BigInt,
    #[serde(with = "hex_vec")]
    values: Vec<BigInt>,
}

#[derive(Debug, Serialize)]
struct MemoryPageFacts {
    regular_page: Option<MemoryPageRegular>,
    continuous_pages: Vec<MemoryPageContinuous>,
}

/// Fact topology for GPS verifier task metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FactTopology {
    pub tree_structure: Vec<u8>,
    pub page_sizes: Vec<usize>,
}

/// Fact topologies file format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FactTopologiesFile {
    pub fact_topologies: Vec<FactTopology>,
}

#[derive(Debug, Serialize)]
struct VerifierInput {
    #[serde(with = "hex_vec")]
    proof_params: Vec<BigInt>,
    #[serde(with = "hex_vec")]
    proof: Vec<BigInt>,
    #[serde(with = "hex_vec")]
    public_input: Vec<BigInt>,
    #[serde(with = "hex")]
    z: BigInt,
    #[serde(with = "hex")]
    alpha: BigInt,
    memory_page_facts: MemoryPageFacts,
    #[serde(with = "hex_vec")]
    task_metadata: Vec<BigInt>,
}

mod hex_vec {
    use num_bigint::BigInt;
    use serde::ser::SerializeSeq;
    use serde::Serializer;

    pub fn serialize<S>(vec: &[BigInt], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut seq = serializer.serialize_seq(Some(vec.len()))?;
        for item in vec {
            let hex_str = format!("0x{:x}", item);
            seq.serialize_element(&hex_str)?;
        }
        seq.end()
    }
}

mod hex {
    use num_bigint::BigInt;
    use serde::Serializer;

    pub fn serialize<S>(val: &BigInt, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let hex_str = format!("0x{:x}", val);
        serializer.serialize_str(&hex_str)
    }
}

fn parse_annotated_proof(path: &str) -> AnnotatedProof {
    let content = fs::read_to_string(path).expect(&format!("Failed to read file: {}", path));
    serde_json::from_str(&content).expect(&format!("Failed to parse JSON from: {}", path))
}

fn extract_interaction_elements(annotations: &[String]) -> (BigInt, BigInt) {
    let pattern = Regex::new(
        r"V->P: /cpu air/STARK/Interaction: Interaction element #\d+: Field Element\(0x([0-9a-f]+)\)"
    ).unwrap();

    let mut elements = Vec::new();
    for line in annotations {
        for cap in pattern.captures_iter(line) {
            if let Some(hex_str) = cap.get(1) {
                let value = BigInt::parse_bytes(hex_str.as_str().as_bytes(), 16)
                    .expect("Failed to parse hex string");
                elements.push(value);
            }
        }
    }

    if elements.len() < 2 {
        panic!("Could not find interaction elements in annotations");
    }

    (elements[0].clone(), elements[1].clone())
}

fn decode_hex(s: &str) -> Vec<u8> {
    let hex_clean = s.strip_prefix("0x").unwrap_or(s);
    (0..hex_clean.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex_clean[i..i + 2.min(hex_clean.len() - i)], 16).unwrap_or(0))
        .collect()
}

fn proof_hex_to_int_list(proof_hex: &str) -> Vec<BigInt> {
    let mut proof_bytes = decode_hex(proof_hex);

    // Pad to multiple of 32 bytes
    while proof_bytes.len() % 32 != 0 {
        proof_bytes.push(0);
    }

    // Convert to list of uint256 (big-endian)
    let mut proof = Vec::new();
    for chunk in proof_bytes.chunks(32) {
        let mut bytes_32 = [0u8; 32];
        bytes_32[32 - chunk.len()..].copy_from_slice(chunk);
        let value = BigInt::from_bytes_be(num_bigint::Sign::Plus, &bytes_32);
        proof.push(value);
    }

    proof
}

fn serialize_segments(public_input: &PublicInput) -> Vec<BigInt> {
    let segment_names = vec![
        "program",
        "execution",
        "output",
        "pedersen",
        "range_check",
        "ecdsa",
        "bitwise",
        "ec_op",
        "keccak",
        "poseidon",
    ];

    let mut result = Vec::new();
    for name in segment_names {
        if let Some(seg) = public_input.memory_segments.get(name) {
            result.push(BigInt::from(seg.begin_addr));
            result.push(BigInt::from(seg.stop_ptr));
        }
    }

    result
}

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    hasher.update(data);
    hasher.finalize().into()
}

fn calculate_product(
    prod: &BigInt,
    z: &BigInt,
    alpha: &BigInt,
    memory_address: &BigInt,
    memory_value: &BigInt,
    prime: &BigInt,
) -> BigInt {
    // Compute: prod * (z - (memory_address + alpha * memory_value)) mod prime
    let lin_comb = (memory_address + alpha * memory_value) % prime;
    let factor = (z - &lin_comb + prime) % prime; // Ensure positive mod
    (prod * factor) % prime
}

fn proof_params(annotated_proof: &AnnotatedProof) -> Vec<BigInt> {
    let fri_params = &annotated_proof.proof_parameters.stark.fri;
    let stark_params = &annotated_proof.proof_parameters.stark;

    let mut params = vec![
        BigInt::from(fri_params.n_queries),
        BigInt::from(stark_params.log_n_cosets),
        BigInt::from(fri_params.proof_of_work_bits),
    ];

    // Last layer degree bound (log2)
    let last_layer_deg_bound = fri_params.last_layer_degree_bound;
    let ceil_log2 = (last_layer_deg_bound as f64).log2().ceil() as u32;
    params.push(BigInt::from(ceil_log2));

    // FRI step list
    params.push(BigInt::from(fri_params.fri_step_list.len()));
    for &step in &fri_params.fri_step_list {
        params.push(BigInt::from(step));
    }

    params
}

fn prepare_memory_page_facts(annotated_proof: &AnnotatedProof) -> MemoryPageFacts {
    let mut pages: HashMap<u64, Vec<(BigInt, BigInt)>> = HashMap::new();

    // Group memory cells by page
    for cell in &annotated_proof.public_input.public_memory {
        let page = cell.page;
        let address = BigInt::from(cell.address);
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        pages
            .entry(page as u64)
            .or_insert_with(Vec::new)
            .push((address, value));
    }

    // Prepare regular page (page 0)
    let regular_page = pages.remove(&0).map(|cells| {
        let mut memory_pairs = Vec::new();
        for (addr, val) in cells {
            memory_pairs.push(addr);
            memory_pairs.push(val);
        }
        MemoryPageRegular { memory_pairs }
    });

    // Prepare continuous pages (page > 0)
    let mut continuous_pages = Vec::new();
    let mut page_numbers: Vec<u64> = pages.keys().cloned().collect();
    page_numbers.sort();

    for page_num in page_numbers {
        let cells = pages[&page_num].clone();

        // Find min and max address
        let mut min_addr: Option<&BigInt> = None;
        let mut max_addr: Option<&BigInt> = None;

        for (addr, _) in &cells {
            if min_addr.is_none() || addr < min_addr.unwrap() {
                min_addr = Some(addr);
            }
            if max_addr.is_none() || addr > max_addr.unwrap() {
                max_addr = Some(addr);
            }
        }

        let start_addr = min_addr.unwrap().clone();
        let end_addr = max_addr.unwrap().clone();

        // Create continuous values array: [value at minAddr, value at minAddr+1, ..., value at maxAddr]
        let size = &end_addr - &start_addr + BigInt::one();
        // Convert size to usize safely
        let size_usize = size
            .to_string()
            .parse::<usize>()
            .unwrap_or_else(|_| panic!("Page {} size too large for usize", page_num));

        let mut values = vec![BigInt::zero(); size_usize];

        for (addr, val) in &cells {
            let offset_big = addr - &start_addr;
            let offset = offset_big
                .to_string()
                .parse::<usize>()
                .unwrap_or_else(|_| panic!("Offset too large for usize"));
            if offset < values.len() {
                values[offset] = val.clone();
            }
        }

        continuous_pages.push(MemoryPageContinuous { start_addr, values });
    }

    MemoryPageFacts {
        regular_page,
        continuous_pages,
    }
}

// Prepare public input WITHOUT page products (for hash calculation)
// This MUST match the format in Stone prover's CpuAirStatement::GetInitialHashChainSeed()
fn prepare_public_input_without_products(
    annotated_proof: &AnnotatedProof,
    memory_page_facts: &MemoryPageFacts,
) -> Vec<BigInt> {
    let public_input = &annotated_proof.public_input;

    // Log n_steps
    let log_n_steps = (public_input.n_steps as f64).log2() as u32;

    // IMPORTANT: First value must be n_verifier_friendly_commitment_layers (from Stone prover format)
    // Try to read from proof_parameters, default to 0 if not present (Stone prover default)
    let n_verifier_friendly_commitment_layers = annotated_proof
        .proof_parameters
        .n_verifier_friendly_commitment_layers
        .map(|v| BigInt::from(v))
        .unwrap_or(BigInt::from(0)); // Default: 0 (same as Stone prover when not specified)

    let mut result = vec![
        n_verifier_friendly_commitment_layers, // Index 0: n_verifier_friendly_commitment_layers
        BigInt::from(log_n_steps),             // Index 1: log_n_steps
        BigInt::from(public_input.rc_min),     // Index 2: rc_min
        BigInt::from(public_input.rc_max),     // Index 3: rc_max
    ];

    // Layout (encode as ASCII bytes to uint256)
    let layout_bytes = public_input.layout.as_bytes();
    let layout_big = BigInt::from_bytes_be(num_bigint::Sign::Plus, layout_bytes);
    result.push(layout_big);

    // Segments
    result.extend(serialize_segments(public_input));

    // Memory pages info WITHOUT products
    let mut pages: HashMap<u64, Vec<BigInt>> = HashMap::new();

    for cell in &public_input.public_memory {
        let page = cell.page;
        let address = BigInt::from(cell.address);
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        let page_data = pages.entry(page as u64).or_insert_with(Vec::new);
        page_data.push(address.clone());
        page_data.push(value.clone());
    }

    // Add padding (from first cell)
    if let Some(first_cell) = public_input.public_memory.first() {
        let padding_addr = BigInt::from(first_cell.address);
        let padding_val = BigInt::parse_bytes(
            first_cell
                .value
                .strip_prefix("0x")
                .unwrap_or(&first_cell.value)
                .as_bytes(),
            16,
        )
        .expect("Failed to parse padding value");
        eprintln!(
            "DEBUG: Adding padding_addr={:x}, padding_val={:x}",
            padding_addr, padding_val
        );
        eprintln!("DEBUG: result.len() before padding: {}", result.len());
        result.push(padding_addr.clone());
        result.push(padding_val.clone());
        eprintln!(
            "DEBUG: result[{}]={:x}, result[{}]={:x}",
            result.len() - 2,
            result[result.len() - 2],
            result.len() - 1,
            result[result.len() - 1]
        );
    } else {
        panic!("No first cell found in public memory");
    }

    // Add number of pages
    let n_pages = if memory_page_facts.regular_page.is_some() {
        1 + memory_page_facts.continuous_pages.len()
    } else {
        memory_page_facts.continuous_pages.len()
    };
    result.push(BigInt::from(n_pages));

    // Sort pages by page number (page 0 first, then 1, 2, etc.)
    let mut page_numbers: Vec<u64> = pages.keys().cloned().collect();
    page_numbers.sort();

    // Add page info (size, hash, address if > 0) WITHOUT products
    for (idx, &page_num) in page_numbers.iter().enumerate() {
        let page = &pages[&page_num];

        // Calculate page hash using memory_pairs from memory_page_facts
        let page_hash = if idx == 0 && page_num == 0 {
            // Regular page (page 0): use memory_pairs from memory_page_facts
            if let Some(ref regular_page) = memory_page_facts.regular_page {
                let memory_pairs = &regular_page.memory_pairs;
                // Compute hash exactly as MemoryPageFactRegistry does: keccak256(memoryPtr, 0x40 * memorySize)
                let mut page_bytes = Vec::new();
                for val in memory_pairs {
                    let mut bytes_32 = [0u8; 32];
                    let bytes = val.to_bytes_be().1;
                    bytes_32[32 - bytes.len()..].copy_from_slice(&bytes);
                    page_bytes.extend_from_slice(&bytes_32);
                }
                let keccak_hash = keccak256(&page_bytes);
                BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak_hash)
            } else {
                panic!("No regular page found in memory page facts");
            }
        } else {
            println!("Continuous page: {:?}", page);
            // Continuous page: add address first, then hash values only
            result.push(page[0].clone()); // First address
            let values: Vec<&BigInt> = page.iter().skip(1).step_by(2).collect();
            let mut values_bytes = Vec::new();
            for val in values {
                let mut bytes_32 = [0u8; 32];
                let bytes = val.to_bytes_be().1;
                bytes_32[32 - bytes.len()..].copy_from_slice(&bytes);
                values_bytes.extend_from_slice(&bytes_32);
            }
            let keccak_hash = keccak256(&values_bytes);
            BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak_hash)
        };

        result.push(BigInt::from(page.len() / 2)); // Page size
        result.push(page_hash);
    }

    // Note: page products are NOT added here - they will be added after computing z and alpha
    eprintln!(
        "DEBUG: prepare_public_input_without_products returns {} elements",
        result.len()
    );
    eprintln!("DEBUG: Last 10 elements:");
    for i in (result.len().saturating_sub(10))..result.len() {
        eprintln!("  [{}] = {:x}", i, result[i]);
    }
    result
}

/// Extract program output from public memory
fn extract_program_output(public_input: &PublicInput) -> Vec<BigInt> {
    let output_segment = public_input
        .memory_segments
        .get("output")
        .expect("Missing output segment");

    let begin = output_segment.begin_addr;
    let stop = output_segment.stop_ptr;

    // Build memory map from public_memory
    let mut memory: HashMap<u64, BigInt> = HashMap::new();
    for cell in &public_input.public_memory {
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));
        memory.insert(cell.address as u64, value);
    }

    let mut output = Vec::new();
    for addr in begin..stop {
        if let Some(value) = memory.get(&addr) {
            output.push(value.clone());
        } else {
            eprintln!("WARNING: Missing value for output address {}", addr);
            output.push(BigInt::zero());
        }
    }
    output
}

/// Generate task metadata for GPS verifier from fact topologies
fn generate_tasks_metadata(
    public_input: &PublicInput,
    fact_topologies: &[FactTopology],
) -> Vec<BigInt> {
    // If no fact_topologies, this is a simple proof without bootloader
    if fact_topologies.is_empty() {
        println!("No fact_topologies - simple proof without bootloader");
        return vec![BigInt::zero()]; // nTasks = 0
    }

    let output = extract_program_output(public_input);
    println!("Program output length: {}", output.len());
    println!(
        "Program output: {:?}",
        output
            .iter()
            .map(|x| format!("0x{:x}", x))
            .collect::<Vec<_>>()
    );

    // Simple bootloader output structure:
    // [0]: nTasks
    // [1]: outputSize (for task 0)
    // [2]: programHash (for task 0)
    // [3..outputSize]: task output data
    //
    // taskMetadata structure for GPS verifier:
    // [0]: nTasks
    // For each task: outputSize, programHash, nTreePairs, tree_structure...
    // NOTE: bootloader config is in the proof OUTPUT, NOT in taskMetadata!

    // Detect full bootloader vs simple bootloader format:
    // Full bootloader: [bootloaderProgramHash, hashedVerifiers, nTasks, ...]
    // Simple bootloader: [nTasks, outputSize, programHash, ...]
    // Full bootloader has large values at indices 0 and 1 (hashes), simple has small nTasks at 0
    let is_full_bootloader = output.len() >= 3 && {
        let val0 = &output[0];
        // If output[0] > 2^32, it's likely a hash (full bootloader)
        val0 > &BigInt::from(0x100000000u64)
    };

    let (n_tasks, tasks_start_idx) = if is_full_bootloader {
        println!("Detected FULL bootloader format (with bootloader_config prefix)");
        // Full bootloader: nTasks at index 2, tasks start at index 3
        let n = output
            .get(2)
            .map(|v| v.to_string().parse::<usize>().unwrap_or(0))
            .unwrap_or(0);
        (n, 3usize)
    } else {
        println!("Detected SIMPLE bootloader format");
        // Simple bootloader: nTasks at index 0, tasks start at index 1
        let n = output
            .get(0)
            .map(|v| v.to_string().parse::<usize>().unwrap_or(0))
            .unwrap_or(0);
        (n, 1usize)
    };

    println!("n_tasks: {}", n_tasks);

    if n_tasks != fact_topologies.len() {
        eprintln!(
            "WARNING: n_tasks ({}) != fact_topologies.len() ({})",
            n_tasks,
            fact_topologies.len()
        );
    }

    // Auto-detect if output actually contains bootloader config
    // Cairo PIE bootloader doesn't write bootloader config to output
    // RunProgramTask bootloader does write it
    // Check if first element is a small number (n_tasks) or large hash`

    // Build task_metadata - starts with nTasks (no bootloader config here!)
    let mut task_metadata = vec![BigInt::from(n_tasks)];
    // Tasks start after bootloader header
    let mut ptr = tasks_start_idx;

    for (i, fact_topology) in fact_topologies.iter().enumerate() {
        if ptr >= output.len() {
            eprintln!("ERROR: Output index out of bounds at task {}", i);
            break;
        }

        let task_output_size = output[ptr].to_string().parse::<usize>().unwrap_or(0);
        let program_hash = output.get(ptr + 1).cloned().unwrap_or(BigInt::zero());

        println!(
            "Task {}: outputSize={}, programHash=0x{:x}",
            i, task_output_size, program_hash
        );

        task_metadata.push(BigInt::from(task_output_size));
        task_metadata.push(program_hash);

        // Add tree structure info: nTreePairs, then pairs
        let n_tree_pairs = fact_topology.tree_structure.len() / 2;
        task_metadata.push(BigInt::from(n_tree_pairs));

        for &val in &fact_topology.tree_structure {
            task_metadata.push(BigInt::from(val));
        }

        ptr += task_output_size;
    }

    println!(
        "Generated task_metadata with {} elements",
        task_metadata.len()
    );
    task_metadata
}

/// Try to load fact topologies from file
fn load_fact_topologies(base_path: &str) -> Vec<FactTopology> {
    // Try multiple possible paths
    let possible_paths = vec![
        format!(
            "{}/fact_topologies.json",
            std::path::Path::new(base_path)
                .parent()
                .unwrap_or(std::path::Path::new("."))
                .display()
        ),
        "fact_topologies.json".to_string(),
        "bootloader/fact_topologies.json".to_string(),
    ];

    for path in &possible_paths {
        if let Ok(content) = fs::read_to_string(path) {
            if let Ok(fact_topologies_file) = serde_json::from_str::<FactTopologiesFile>(&content) {
                println!("Loaded fact_topologies from: {}", path);
                return fact_topologies_file.fact_topologies;
            }
        }
    }

    println!("No fact_topologies.json found - using empty (simple proof mode)");
    Vec::new()
}

fn prepare_verifier_input(annotated_proof_path: &str) -> VerifierInput {
    let annotated_proof = parse_annotated_proof(annotated_proof_path);

    // Convert proof
    let proof = proof_hex_to_int_list(&annotated_proof.proof_hex);

    // Prepare proof parameters
    let proof_params = proof_params(&annotated_proof);

    // IMPORTANT: Prepare memory page facts FIRST (without z and alpha)
    // This prepares the data structure, but products will be computed later
    let memory_page_facts = prepare_memory_page_facts(&annotated_proof);

    // Prepare public input WITHOUT page products (for hash calculation)
    let public_input_without_products =
        prepare_public_input_without_products(&annotated_proof, &memory_page_facts);

    // Extract z and alpha from annotations
    // NOTE: We use annotations instead of computing from hash because the verifier
    // may compute different values due to PRNG implementation differences
    let (z, alpha) = extract_interaction_elements(&annotated_proof.annotations);
    println!("Using z from annotations: 0x{:x}", z);
    println!("Using alpha from annotations: 0x{:x}", alpha);

    // Now compute page products using computed z and alpha
    let mut public_input = public_input_without_products.clone();

    // Calculate page products
    let k_modulus =
        BigInt::parse_bytes(K_MODULUS_STR.strip_prefix("0x").unwrap().as_bytes(), 16).unwrap();

    let mut page_prods: HashMap<u64, BigInt> = HashMap::new();

    for cell in &annotated_proof.public_input.public_memory {
        let page = cell.page;
        let address = BigInt::from(cell.address);
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        let prod = page_prods.entry(page as u64).or_insert_with(BigInt::one);
        *prod = calculate_product(prod, &z, &alpha, &address, &value, &k_modulus);
    }

    // Add page products to public_input (in sorted order)
    // NOTE: Products must be added AFTER all page info (address/size/hash)
    let mut page_numbers: Vec<u64> = page_prods.keys().cloned().collect();
    page_numbers.sort();
    eprintln!("DEBUG: Adding {} products", page_numbers.len());
    for &page_num in &page_numbers {
        eprintln!(
            "DEBUG: Adding product for page {}: {:x}",
            page_num, page_prods[&page_num]
        );
        public_input.push(page_prods[&page_num].clone());
    }
    eprintln!("DEBUG: Final public_input length: {}", public_input.len());

    // Load fact topologies and generate task metadata
    let fact_topologies = load_fact_topologies(annotated_proof_path);
    let task_metadata = generate_tasks_metadata(&annotated_proof.public_input, &fact_topologies);

    VerifierInput {
        proof_params,
        proof,
        public_input,
        z,
        alpha,
        memory_page_facts,
        task_metadata,
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: prepare-input <annotated_proof.json> [output.json]");
        std::process::exit(1);
    }

    let annotated_proof_path = &args[1];
    let output_path = args.get(2).map(|s| s.as_str()).unwrap_or("input.json");

    println!("Preparing input from {}...", annotated_proof_path);
    let verifier_input = prepare_verifier_input(annotated_proof_path);

    let json_output =
        serde_json::to_string_pretty(&verifier_input).expect("Failed to serialize output");

    fs::write(output_path, json_output)
        .expect(&format!("Failed to write output to: {}", output_path));

    println!("Input prepared and saved to {}", output_path);
    println!("Proof params length: {}", verifier_input.proof_params.len());
    println!("Proof length: {}", verifier_input.proof.len());
    println!("Public input length: {}", verifier_input.public_input.len());
}
