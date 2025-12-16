use clap::{Parser, Subcommand};
use std::process::Command;

#[derive(Parser)]
#[command(name = "deploy")]
#[command(about = "Deploy STARK verifier contracts to Ethereum networks")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Deploy to Sepolia testnet
    Sepolia {
        /// Dry run (simulate without broadcasting)
        #[arg(long)]
        dry: bool,
    },
    /// Deploy to Base Sepolia testnet
    BaseSepolia {
        /// Dry run (simulate without broadcasting)
        #[arg(long)]
        dry: bool,
    },
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    
    let rpc_url = match &cli.command {
        Commands::Sepolia { .. } => std::env::var("SEPOLIA_RPC_URL")
            .expect("SEPOLIA_RPC_URL must be set in .env"),
        Commands::BaseSepolia { .. } => std::env::var("BASE_SEPOLIA_RPC_URL")
            .expect("BASE_SEPOLIA_RPC_URL must be set in .env"),
    };
    
    let is_dry = matches!(&cli.command, Commands::Sepolia { dry } | Commands::BaseSepolia { dry } if *dry);
    
    let mut cmd = Command::new("forge");
    cmd.arg("script")
        .arg("script/Deploy.s.sol:DeployScript")
        .arg("--rpc-url")
        .arg(&rpc_url)
        .arg("-vvvv");
    
    if !is_dry {
        cmd.arg("--broadcast");
        println!("🚀 Deploying to network...");
    } else {
        println!("🔍 Simulating deployment (dry run)...");
    }
    
    let status = cmd.status()?;
    
    if status.success() {
        if !is_dry {
            println!("✅ Deployment complete!");
        } else {
            println!("✅ Simulation complete!");
        }
        Ok(())
    } else {
        Err("Deployment failed".into())
    }
}

