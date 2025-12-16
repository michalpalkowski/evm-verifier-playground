use clap::Parser;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about = "Calculate FRI step sizes for STARK proofs", long_about = None)]
struct Args {
    /// Path to cpu_air_params.json file
    #[arg(short, long)]
    params_file: PathBuf,

    /// Degree bound (if not specified, reads from file or uses default)
    #[arg(short, long)]
    degree_bound: Option<u32>,

    /// Number of steps (if not specified, calculates from trace length)
    #[arg(short, long)]
    n_steps: Option<u32>,

    /// Path to public_input.json to read trace_length
    #[arg(long)]
    public_input: Option<PathBuf>,

    /// Output file (if not specified, updates input file)
    #[arg(short, long)]
    output: Option<PathBuf>,

    /// Just print the calculated steps without modifying file
    #[arg(long)]
    dry_run: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct CpuAirParams {
    field: String,
    stark: StarkParams,
    use_extension_field: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct StarkParams {
    fri: FriParams,
    log_n_cosets: u32,
}

#[derive(Debug, Serialize, Deserialize)]
struct FriParams {
    fri_step_list: Vec<u32>,
    last_layer_degree_bound: u32,
    n_queries: u32,
    proof_of_work_bits: u32,
}

fn calculate_fri_step_list(n_steps: u32, degree_bound: u32) -> Vec<u32> {
    let fri_degree = ((n_steps as f64 / degree_bound as f64).log2().round() as u32) + 4;
    let mut steps = vec![0];

    // Add as many steps of size 4 as possible
    let num_fours = fri_degree / 4;
    steps.extend(vec![4; num_fours as usize]);

    // Add remainder if any
    let remainder = fri_degree % 4;
    if remainder != 0 {
        steps.push(remainder);
    }

    steps
}

fn read_n_steps_from_public_input(path: &PathBuf) -> Result<u32, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let json: Value = serde_json::from_str(&content)?;

    // Try to find n_steps directly
    if let Some(n_steps) = json.get("n_steps") {
        return Ok(n_steps.as_u64().ok_or("Invalid n_steps")? as u32);
    }

    // Alternative: try trace_length
    if let Some(trace_length) = json.get("trace_length") {
        return Ok(trace_length.as_u64().ok_or("Invalid trace_length")? as u32);
    }

    // Try in public_memory
    if let Some(trace_length) = json
        .get("public_memory")
        .and_then(|m| m.get("trace_length"))
    {
        return Ok(trace_length.as_u64().ok_or("Invalid trace_length")? as u32);
    }

    Err("Could not find n_steps or trace_length in public_input.json".into())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    // Read the params file
    let params_content = fs::read_to_string(&args.params_file)?;
    let mut params: CpuAirParams = serde_json::from_str(&params_content)?;

    // Get degree_bound (from args, file, or default)
    let degree_bound = args
        .degree_bound
        .unwrap_or(params.stark.fri.last_layer_degree_bound);

    // Get n_steps (from args, public_input, or default)
    let n_steps = if let Some(n) = args.n_steps {
        n
    } else if let Some(ref public_input_path) = args.public_input {
        match read_n_steps_from_public_input(public_input_path) {
            Ok(n_steps) => {
                println!(
                    "Read n_steps from {}: {}",
                    public_input_path.display(),
                    n_steps
                );
                n_steps
            }
            Err(e) => {
                eprintln!("Warning: Could not read n_steps: {}. Using default.", e);
                panic!("Could not read n_steps from public_input.json");
            }
        }
    } else {
        // Default: calculate from typical values
        panic!("No n_steps provided and could not read from public_input.json");
    };

    // Calculate FRI steps
    let new_fri_steps = calculate_fri_step_list(n_steps, degree_bound);

    println!("Calculating FRI step list:");
    println!("  n_steps: {}", n_steps);
    println!("  degree_bound: {}", degree_bound);
    println!(
        "  fri_degree: {}",
        ((n_steps as f64 / degree_bound as f64).log2().round() as u32) + 4
    );
    println!("  calculated fri_step_list: {:?}", new_fri_steps);
    println!();

    if args.dry_run {
        println!("Dry run - not modifying files");
        return Ok(());
    }

    // Update params
    params.stark.fri.fri_step_list = new_fri_steps;
    params.stark.fri.last_layer_degree_bound = degree_bound;

    // Write output
    let output_path = args.output.unwrap_or(args.params_file);
    let output_content = serde_json::to_string_pretty(&params)?;
    fs::write(&output_path, output_content)?;

    println!("✓ Updated {}", output_path.display());

    Ok(())
}
