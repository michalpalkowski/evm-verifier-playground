use clap::{Parser, Subcommand};
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Parser)]
#[command(name = "test")]
#[command(about = "Test STARK verifier with example programs")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Test a program example (fibonacci, factorial)
    Example {
        /// Program name (fibonacci or factorial)
        program: String,
        /// Test bootloader version
        #[arg(long)]
        bootloader: bool,
    },
    /// Run all Forge tests
    All {
        /// Show gas report
        #[arg(long)]
        gas: bool,
    },
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    
    match cli.command {
        Commands::Example { program, bootloader } => {
            let example_dir = if bootloader {
                format!("examples/{}-bootloader", program)
            } else {
                format!("examples/{}", program)
            };
            
            let input_json_path = Path::new(&example_dir).join("input.json");
            
            if !input_json_path.exists() {
                eprintln!("❌ Error: input.json not found in {}", example_dir);
                eprintln!("Available examples: fibonacci, factorial");
                if bootloader {
                    eprintln!("  make bootloader PROGRAM={}", program);
                } else {
                    eprintln!("  make simple-flow PROGRAM={} LAYOUT=starknet", program);
                }
                eprintln!("  cp work/{}-starknet/input.json ../ethereum_verifier/{}/", program, example_dir);
                return Err(format!("input.json not found in {}", example_dir).into());
            }
            
            println!("🧪 Testing program: {} ({})", program, if bootloader { "bootloader" } else { "regular" });
            
            // Copy input.json to root
            fs::copy(&input_json_path, "input.json")?;
            println!("  Copied {} to input.json", input_json_path.display());
            
            // Run forge test
            let mut cmd = Command::new("forge");
            cmd.arg("test").arg("--match-test").arg("test_VerifyProof");
            
            let status = cmd.status()?;
            
            if status.success() {
                println!("✅ Test complete");
                Ok(())
            } else {
                Err("Test failed".into())
            }
        }
        Commands::All { gas } => {
            println!("🧪 Running all Forge tests...");
            
            let mut cmd = Command::new("forge");
            cmd.arg("test");
            
            if gas {
                cmd.arg("--gas-report");
                println!("  (with gas report)");
            }
            
            let status = cmd.status()?;
            
            if status.success() {
                println!("✅ All tests passed");
                Ok(())
            } else {
                Err("Tests failed".into())
            }
        }
    }
}

