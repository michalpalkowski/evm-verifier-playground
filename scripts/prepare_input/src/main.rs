use prepare_input::prepare_verifier_input;
use std::env;
use std::fs;

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
