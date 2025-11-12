// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/layout_starknet/CpuVerifier.sol";
import "../src/common/MemoryPageFactRegistry.sol";
import "../src/layout_starknet/CpuOods.sol";
import "../src/layout_starknet/CpuConstraintPoly.sol";

// Periodic column imports
import "evm-verifier-columns/PedersenHashPointsXColumn.sol";
import "evm-verifier-columns/PedersenHashPointsYColumn.sol";
import "evm-verifier-columns/EcdsaPointsXColumn.sol";
import "evm-verifier-columns/EcdsaPointsYColumn.sol";
import "evm-verifier-columns/PoseidonPoseidonFullRoundKey0Column.sol";
import "evm-verifier-columns/PoseidonPoseidonFullRoundKey1Column.sol";
import "evm-verifier-columns/PoseidonPoseidonFullRoundKey2Column.sol";
import "evm-verifier-columns/PoseidonPoseidonPartialRoundKey0Column.sol";
import "evm-verifier-columns/PoseidonPoseidonPartialRoundKey1Column.sol";

contract DeployScript is Script {
    // Security parameters (matching test configuration)
    uint256 constant NUM_SECURITY_BITS = 60;
    uint256 constant MIN_PROOF_OF_WORK_BITS = 20;

    function run() external {
        // Read private key as string and add 0x prefix if needed
        string memory pkString = vm.envString("PRIVATE_KEY");
        if (bytes(pkString).length > 2 && bytes(pkString)[0] == "0" && bytes(pkString)[1] == "x") {
            // Already has 0x prefix
        } else {
            // Add 0x prefix
            pkString = string(abi.encodePacked("0x", pkString));
        }
        uint256 deployerPrivateKey = vm.parseUint(pkString);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying STARK Verifier to Sepolia...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));

        // Step 1: Deploy MemoryPageFactRegistry
        console.log("\n1. Deploying MemoryPageFactRegistry...");
        MemoryPageFactRegistry factRegistry = new MemoryPageFactRegistry();
        console.log("  MemoryPageFactRegistry:", address(factRegistry));

        // Step 2: Deploy CpuOods
        console.log("\n2. Deploying CpuOods...");
        CpuOods oodsContract = new CpuOods();
        console.log("  CpuOods:", address(oodsContract));

        // Step 3: Deploy CpuConstraintPoly
        console.log("\n3. Deploying CpuConstraintPoly...");
        CpuConstraintPoly constraintPoly = new CpuConstraintPoly();
        console.log("  CpuConstraintPoly:", address(constraintPoly));

        // Step 4: Deploy Periodic Columns
        console.log("\n4. Deploying Periodic Columns...");
        address[9] memory periodicColumns;

        periodicColumns[0] = address(new PedersenHashPointsXColumn());
        console.log("  PedersenHashPointsXColumn:", periodicColumns[0]);

        periodicColumns[1] = address(new PedersenHashPointsYColumn());
        console.log("  PedersenHashPointsYColumn:", periodicColumns[1]);

        periodicColumns[2] = address(new EcdsaPointsXColumn());
        console.log("  EcdsaPointsXColumn:", periodicColumns[2]);

        periodicColumns[3] = address(new EcdsaPointsYColumn());
        console.log("  EcdsaPointsYColumn:", periodicColumns[3]);

        periodicColumns[4] = address(new PoseidonPoseidonFullRoundKey0Column());
        console.log("  PoseidonPoseidonFullRoundKey0Column:", periodicColumns[4]);

        periodicColumns[5] = address(new PoseidonPoseidonFullRoundKey1Column());
        console.log("  PoseidonPoseidonFullRoundKey1Column:", periodicColumns[5]);

        periodicColumns[6] = address(new PoseidonPoseidonFullRoundKey2Column());
        console.log("  PoseidonPoseidonFullRoundKey2Column:", periodicColumns[6]);

        periodicColumns[7] = address(new PoseidonPoseidonPartialRoundKey0Column());
        console.log("  PoseidonPoseidonPartialRoundKey0Column:", periodicColumns[7]);

        periodicColumns[8] = address(new PoseidonPoseidonPartialRoundKey1Column());
        console.log("  PoseidonPoseidonPartialRoundKey1Column:", periodicColumns[8]);

        // Step 5: Prepare aux polynomials array (CpuConstraintPoly + 9 periodic columns)
        address[] memory auxPolynomials = new address[](10);
        auxPolynomials[0] = address(constraintPoly);  // Index 0: CpuConstraintPoly
        for (uint256 i = 0; i < 9; i++) {
            auxPolynomials[i + 1] = periodicColumns[i];  // Indices 1-9: periodic columns
        }

        // Step 6: Deploy main CpuVerifier
        console.log("\n5. Deploying CpuVerifier...");
        CpuVerifier verifier = new CpuVerifier(
            auxPolynomials,
            address(oodsContract),
            address(factRegistry),
            NUM_SECURITY_BITS,
            MIN_PROOF_OF_WORK_BITS
        );
        console.log("  CpuVerifier:", address(verifier));

        vm.stopBroadcast();

        // Save deployment addresses
        console.log("\n===== DEPLOYMENT COMPLETE =====");
        console.log("\nDeployed Addresses:");
        console.log("  MemoryPageFactRegistry:", address(factRegistry));
        console.log("  CpuOods:", address(oodsContract));
        console.log("  CpuConstraintPoly:", address(constraintPoly));
        console.log("  CpuVerifier:", address(verifier));
        console.log("\nPerio columns:");
        for (uint256 i = 0; i < 9; i++) {
            console.log("  ", i, ":", periodicColumns[i]);
        }

        // Save to file for easy reference
        string memory deploymentInfo = string.concat(
            "{\n",
            '  "verifier": "', vm.toString(address(verifier)), '",\n',
            '  "factRegistry": "', vm.toString(address(factRegistry)), '",\n',
            '  "oodsContract": "', vm.toString(address(oodsContract)), '",\n',
            '  "constraintPoly": "', vm.toString(address(constraintPoly)), '"\n',
            "}\n"
        );

        vm.writeFile("deployment-addresses.json", deploymentInfo);
        console.log("\nAddresses saved to deployment-addresses.json");
    }
}
