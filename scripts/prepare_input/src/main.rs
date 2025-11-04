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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PublicInput {
    n_steps: u64,
    rc_min: i64,
    rc_max: i64,
    layout: String,
    memory_segments: HashMap<String, MemorySegment>,
    public_memory: Vec<MemoryCell>,
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

// Compute publicInputHash exactly as verifier does
// Hash is computed from publicInput WITHOUT page products
// Note: Verifier uses keccak256, but stone-prover uses HashBytesWithLength
// For compatibility, we use keccak256 as verifier does
fn compute_public_input_hash(public_input_without_products: &[BigInt]) -> [u8; 32] {
    // Convert BigInt array to bytes for hashing
    // Verifier uses keccak256(add(publicInput, 0x20), publicInputSizeForHash)
    // which means it skips the length field (first 32 bytes) and hashes the rest
    let mut bytes = Vec::new();
    for val in public_input_without_products {
        let mut bytes_32 = [0u8; 32];
        let val_bytes = val.to_bytes_be().1;
        bytes_32[32 - val_bytes.len()..].copy_from_slice(&val_bytes);
        bytes.extend_from_slice(&bytes_32);
    }
    keccak256(&bytes)
}

// Compute z and alpha from publicInputHash using PRNG, exactly as verifier does
// IMPORTANT: Verifier reads trace commitment BEFORE computing z and alpha!
// The trace commitment is read with mix=true, which changes the PRNG state
// We need to read trace commitment from proof and mix it into PRNG
fn compute_interaction_elements_from_hash_and_proof(
    public_input_hash: [u8; 32],
    proof: &[BigInt],
) -> (BigInt, BigInt) {
    let k_modulus =
        BigInt::parse_bytes(K_MODULUS_STR.strip_prefix("0x").unwrap().as_bytes(), 16).unwrap();

    // K_MONTGOMERY_R_INV from PrimeFieldElement0.sol
    let k_montgomery_r_inv = BigInt::parse_bytes(
        "0x40000000000001100000000000012100000000000000000000000000000000"
            .strip_prefix("0x")
            .unwrap()
            .as_bytes(),
        16,
    )
    .unwrap();

    // BOUND = 31 * K_MODULUS (from VerifierChannel.sendFieldElements)
    let bound = &k_modulus * BigInt::from(31u32);

    // PRNG state: digest = publicInputHash, counter = 0
    let mut digest = public_input_hash;
    let mut counter = 0u64;

    // IMPORTANT: Verifier reads trace commitment BEFORE computing z and alpha!
    // readHash(channelPtr, true) with mix=true changes PRNG state:
    // digest += 1, counter = val, digest = keccak256(digest + 1 || val), counter = 0
    // Read first 32 bytes from proof as trace commitment
    if proof.len() > 0 {
        let trace_commitment = &proof[0];
        let mut trace_commitment_bytes = [0u8; 32];
        let val_bytes = trace_commitment.to_bytes_be().1;
        trace_commitment_bytes[32 - val_bytes.len()..].copy_from_slice(&val_bytes);

        // Simulate readHash with mix=true exactly as verifier does:
        // digest += 1 (as uint256, so modulo 2^256)
        // In Solidity: mstore(digestPtr, add(mload(digestPtr), 1))
        // This is just adding 1 to the 32-byte value
        let mut digest_big = BigInt::from_bytes_be(num_bigint::Sign::Plus, &digest);
        digest_big = digest_big + BigInt::from(1u32);

        // Take modulo 2^256 to simulate uint256 overflow
        let two_256 = BigInt::from(1u32) << 256;
        digest_big = digest_big % two_256;

        let mut digest_plus_one_bytes = [0u8; 32];
        let digest_val_bytes = digest_big.to_bytes_be().1;
        digest_plus_one_bytes[32 - digest_val_bytes.len()..].copy_from_slice(&digest_val_bytes);

        // keccak256(digest + 1 || val) where val is trace_commitment
        // In Solidity: keccak256(digestPtr, 0x40) where 0x40 = 64 bytes = digest + counter
        let mut mix_input = Vec::new();
        mix_input.extend_from_slice(&digest_plus_one_bytes);
        mix_input.extend_from_slice(&trace_commitment_bytes);
        digest = keccak256(&mix_input);
        counter = 0;
    }

    let mut interaction_elements = Vec::new();

    // Generate 6 interaction elements (we only need first 2 for z and alpha)
    for _ in 0..2 {
        let mut field_element = BigInt::from_bytes_be(num_bigint::Sign::Plus, &digest);

        // Keep generating until field_element < BOUND
        while field_element >= bound {
            // Increment counter
            counter += 1;

            // Compute keccak256(digest, counter)
            let mut counter_bytes = [0u8; 32];
            let counter_val = counter.to_be_bytes();
            counter_bytes[32 - counter_val.len()..].copy_from_slice(&counter_val);

            let mut input = Vec::new();
            input.extend_from_slice(&digest);
            input.extend_from_slice(&counter_bytes);

            field_element = BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak256(&input));
            digest = keccak256(&input);
        }

        // Convert from Montgomery form: fieldElement * K_MONTGOMERY_R_INV mod K_MODULUS
        let result = (&field_element * &k_montgomery_r_inv) % &k_modulus;
        interaction_elements.push(result);

        // Update digest and counter for next iteration
        counter += 1;
        let mut counter_bytes = [0u8; 32];
        let counter_val = counter.to_be_bytes();
        counter_bytes[32 - counter_val.len()..].copy_from_slice(&counter_val);
        let mut input = Vec::new();
        input.extend_from_slice(&digest);
        input.extend_from_slice(&counter_bytes);
        digest = keccak256(&input);
    }

    (
        interaction_elements[0].clone(),
        interaction_elements[1].clone(),
    )
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

fn memory_page_public_input_with_facts(
    public_memory: &[MemoryCell],
    z: &BigInt,
    alpha: &BigInt,
    memory_page_facts: &MemoryPageFacts,
) -> Vec<BigInt> {
    let k_modulus =
        BigInt::parse_bytes(K_MODULUS_STR.strip_prefix("0x").unwrap().as_bytes(), 16).unwrap();

    let mut result = Vec::new();
    let mut pages: HashMap<u64, Vec<BigInt>> = HashMap::new();
    let mut page_prods: HashMap<u64, BigInt> = HashMap::new();

    for cell in public_memory {
        let page = cell.page;
        let address = BigInt::parse_bytes(cell.address.as_bytes(), 10)
            .expect(&format!("Failed to parse address: {}", cell.address));
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        let page_data = pages.entry(page).or_insert_with(Vec::new);
        page_data.push(address.clone());
        page_data.push(value.clone());

        let prod = page_prods.entry(page).or_insert_with(BigInt::one);
        *prod = calculate_product(prod, z, alpha, &address, &value, &k_modulus);
    }

    // Add padding (from first cell)
    if let Some(first_cell) = public_memory.first() {
        let padding_addr = BigInt::parse_bytes(first_cell.address.as_bytes(), 10)
            .expect("Failed to parse padding address");
        let padding_val = BigInt::parse_bytes(
            first_cell
                .value
                .strip_prefix("0x")
                .unwrap_or(&first_cell.value)
                .as_bytes(),
            16,
        )
        .expect("Failed to parse padding value");
        result.push(padding_addr);
        result.push(padding_val);
    } else {
        result.push(BigInt::zero());
        result.push(BigInt::zero());
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

    // Add page info (size, hash, address if > 0)
    // IMPORTANT: Use memory_pairs from memory_page_facts to compute hash
    // This ensures hash matches what's used in fact registration
    for (idx, &page_num) in page_numbers.iter().enumerate() {
        let page = &pages[&page_num];

        // Calculate page hash using memory_pairs from memory_page_facts
        let page_hash = if idx == 0 && page_num == 0 {
            // Regular page (page 0): use memory_pairs from memory_page_facts
            if let Some(ref regular_page) = memory_page_facts.regular_page {
                let memory_pairs = &regular_page.memory_pairs;
                eprintln!(
                    "DEBUG: Using memory_pairs from memory_page_facts, count: {}",
                    memory_pairs.len()
                );
                // Compute hash exactly as MemoryPageFactRegistry does: keccak256(memoryPtr, 0x40 * memorySize)
                let mut page_bytes = Vec::new();
                for val in memory_pairs {
                    let mut bytes_32 = [0u8; 32];
                    let bytes = val.to_bytes_be().1;
                    bytes_32[32 - bytes.len()..].copy_from_slice(&bytes);
                    page_bytes.extend_from_slice(&bytes_32);
                }
                let keccak_hash = keccak256(&page_bytes);
                let hash_bigint = BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak_hash);
                eprintln!(
                    "DEBUG: Computed hash from memory_pairs: 0x{:x}",
                    hash_bigint
                );
                hash_bigint
            } else {
                eprintln!("DEBUG: regular_page is None, using fallback");
                // Fallback (should not happen for page 0)
                let mut page_bytes = Vec::new();
                for val in page {
                    let mut bytes_32 = [0u8; 32];
                    let bytes = val.to_bytes_be().1;
                    bytes_32[32 - bytes.len()..].copy_from_slice(&bytes);
                    page_bytes.extend_from_slice(&bytes_32);
                }
                let keccak_hash = keccak256(&page_bytes);
                BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak_hash)
            }
        } else {
            // Continuous page: add address, hash values only
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

    // Add page products (in sorted order)
    for &page_num in &page_numbers {
        result.push(page_prods[&page_num].clone());
    }

    result
}

fn memory_page_public_input(
    public_memory: &[MemoryCell],
    z: &BigInt,
    alpha: &BigInt,
) -> Vec<BigInt> {
    let k_modulus =
        BigInt::parse_bytes(K_MODULUS_STR.strip_prefix("0x").unwrap().as_bytes(), 16).unwrap();

    let mut result = Vec::new();
    let mut pages: HashMap<u64, Vec<BigInt>> = HashMap::new();
    let mut page_prods: HashMap<u64, BigInt> = HashMap::new();

    for cell in public_memory {
        let page = cell.page;
        let address = BigInt::parse_bytes(cell.address.as_bytes(), 10)
            .expect(&format!("Failed to parse address: {}", cell.address));
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        let page_data = pages.entry(page).or_insert_with(Vec::new);
        page_data.push(address.clone());
        page_data.push(value.clone());

        let prod = page_prods.entry(page).or_insert_with(BigInt::one);
        *prod = calculate_product(prod, z, alpha, &address, &value, &k_modulus);
    }

    // Add padding (from first cell)
    if let Some(first_cell) = public_memory.first() {
        let padding_addr = BigInt::parse_bytes(first_cell.address.as_bytes(), 10)
            .expect("Failed to parse padding address");
        let padding_val = BigInt::parse_bytes(
            first_cell
                .value
                .strip_prefix("0x")
                .unwrap_or(&first_cell.value)
                .as_bytes(),
            16,
        )
        .expect("Failed to parse padding value");
        result.push(padding_addr);
        result.push(padding_val);
    } else {
        result.push(BigInt::zero());
        result.push(BigInt::zero());
    }

    // Add number of pages
    result.push(BigInt::from(pages.len()));

    // Sort pages by page number
    let mut page_numbers: Vec<u64> = pages.keys().cloned().collect();
    page_numbers.sort();

    // Add page info (size, hash, address if > 0)
    for (idx, &page_num) in page_numbers.iter().enumerate() {
        let page = &pages[&page_num];

        // Calculate page hash
        // IMPORTANT: This hash MUST match the hash computed by MemoryPageFactRegistry.computeFactHash
        // which uses keccak256(memoryPtr, 0x40 * memorySize) where memoryPtr points to the memoryPairs array
        let page_hash = if idx == 0 {
            // Regular page: hash all pairs (keccak256 of packed pairs)
            // The hash must match what's computed from memory_pairs in prepare_memory_page_facts
            // Ensure we use the same data and format as memory_pairs
            let mut page_bytes = Vec::new();
            for val in page {
                let mut bytes_32 = [0u8; 32];
                let bytes = val.to_bytes_be().1;
                bytes_32[32 - bytes.len()..].copy_from_slice(&bytes);
                page_bytes.extend_from_slice(&bytes_32);
            }
            let keccak_hash = keccak256(&page_bytes);
            BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak_hash)
        } else {
            // Continuous page: add address, hash values only
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

    // Add page products (in sorted order)
    for &page_num in &page_numbers {
        result.push(page_prods[&page_num].clone());
    }

    result
}

fn cairo_aux_input_with_facts(
    annotated_proof: &AnnotatedProof,
    z: &BigInt,
    alpha: &BigInt,
    memory_page_facts: &MemoryPageFacts,
) -> Vec<BigInt> {
    let public_input = &annotated_proof.public_input;

    // Log n_steps
    let log_n_steps = (public_input.n_steps as f64).log2() as u32;

    let mut result = vec![
        BigInt::from(log_n_steps),
        BigInt::from(public_input.rc_min),
        BigInt::from(public_input.rc_max),
    ];

    // Layout (encode as ASCII bytes to uint256)
    let layout_bytes = public_input.layout.as_bytes();
    let layout_big = BigInt::from_bytes_be(num_bigint::Sign::Plus, layout_bytes);
    result.push(layout_big);

    // Segments
    result.extend(serialize_segments(public_input));

    // Memory pages - use memory_page_facts to compute consistent hashes
    result.extend(memory_page_public_input_with_facts(
        &public_input.public_memory,
        z,
        alpha,
        memory_page_facts,
    ));

    result
}

fn cairo_aux_input(annotated_proof: &AnnotatedProof, z: &BigInt, alpha: &BigInt) -> Vec<BigInt> {
    let public_input = &annotated_proof.public_input;

    // Log n_steps
    let log_n_steps = (public_input.n_steps as f64).log2() as u32;

    let mut result = vec![
        BigInt::from(log_n_steps),
        BigInt::from(public_input.rc_min),
        BigInt::from(public_input.rc_max),
    ];

    // Layout (encode as ASCII bytes to uint256)
    // Note: stark-evm-adapter uses from_big_endian without padding
    // So we convert directly from ASCII bytes without padding to match
    let layout_bytes = public_input.layout.as_bytes();
    let layout_big = BigInt::from_bytes_be(num_bigint::Sign::Plus, layout_bytes);
    result.push(layout_big);

    // Segments
    result.extend(serialize_segments(public_input));

    // Memory pages
    result.extend(memory_page_public_input(
        &public_input.public_memory,
        z,
        alpha,
    ));

    // Note: z and alpha are NOT included in publicInput for verifyProofExternal
    // They are computed by the verifier from publicInputHash

    result
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
        let address = BigInt::parse_bytes(cell.address.as_bytes(), 10)
            .expect(&format!("Failed to parse address: {}", cell.address));
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        pages
            .entry(page)
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
        let address = BigInt::parse_bytes(cell.address.as_bytes(), 10)
            .expect(&format!("Failed to parse address: {}", cell.address));
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        let page_data = pages.entry(page).or_insert_with(Vec::new);
        page_data.push(address.clone());
        page_data.push(value.clone());
    }

    // Add padding (from first cell)
    if let Some(first_cell) = public_input.public_memory.first() {
        let padding_addr = BigInt::parse_bytes(first_cell.address.as_bytes(), 10)
            .expect("Failed to parse padding address");
        let padding_val = BigInt::parse_bytes(
            first_cell
                .value
                .strip_prefix("0x")
                .unwrap_or(&first_cell.value)
                .as_bytes(),
            16,
        )
        .expect("Failed to parse padding value");
        result.push(padding_addr);
        result.push(padding_val);
    } else {
        result.push(BigInt::zero());
        result.push(BigInt::zero());
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
                // Fallback (should not happen for page 0)
                let mut page_bytes = Vec::new();
                for val in page {
                    let mut bytes_32 = [0u8; 32];
                    let bytes = val.to_bytes_be().1;
                    bytes_32[32 - bytes.len()..].copy_from_slice(&bytes);
                    page_bytes.extend_from_slice(&bytes_32);
                }
                let keccak_hash = keccak256(&page_bytes);
                BigInt::from_bytes_be(num_bigint::Sign::Plus, &keccak_hash)
            }
        } else {
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
    result
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
        let address = BigInt::parse_bytes(cell.address.as_bytes(), 10)
            .expect(&format!("Failed to parse address: {}", cell.address));
        let value = BigInt::parse_bytes(
            cell.value
                .strip_prefix("0x")
                .unwrap_or(&cell.value)
                .as_bytes(),
            16,
        )
        .expect(&format!("Failed to parse value: {}", cell.value));

        let prod = page_prods.entry(page).or_insert_with(BigInt::one);
        *prod = calculate_product(prod, &z, &alpha, &address, &value, &k_modulus);
    }

    // Add page products to public_input (in sorted order)
    let mut page_numbers: Vec<u64> = page_prods.keys().cloned().collect();
    page_numbers.sort();
    for &page_num in &page_numbers {
        public_input.push(page_prods[&page_num].clone());
    }

    VerifierInput {
        proof_params,
        proof,
        public_input,
        z,
        alpha,
        memory_page_facts,
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
