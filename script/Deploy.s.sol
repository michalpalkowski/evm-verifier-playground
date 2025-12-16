// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/layout_starknet/CpuVerifier.sol";
import "../src/common/MemoryPageFactRegistry.sol";
import "../src/layout_starknet/CpuOods.sol";
import "../src/layout_starknet/CpuConstraintPoly.sol";
import "../src/GpsStatementVerifier/GpsStatementVerifier.sol";
import "../src/common/CairoBootloaderProgram.sol";
import "../src/common/MerkleStatementContract.sol";
import "../src/common/FriStatementContract.sol";

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

        // Deploy all contracts
        DeploymentAddresses memory addrs = _deployAll();

        vm.stopBroadcast();

        // Save deployment addresses
        _saveDeploymentAddresses(addrs);
    }

    struct DeploymentAddresses {
        address verifier;
        address gpsVerifier;
        address factRegistry;
        address oodsContract;
        address constraintPoly;
        address bootloaderProgram;
        address merkleStatementContract;
        address friStatementContract;
    }

    function _deployAll() internal returns (DeploymentAddresses memory addrs) {
        // Step 1: Deploy MemoryPageFactRegistry
        console.log("\n1. Deploying MemoryPageFactRegistry...");
        addrs.factRegistry = address(new MemoryPageFactRegistry());
        console.log("  MemoryPageFactRegistry:", addrs.factRegistry);

        // Step 1.5: Deploy MerkleStatementContract and FriStatementContract
        console.log("\n1.5. Deploying MerkleStatementContract...");
        addrs.merkleStatementContract = address(new MerkleStatementContract());
        console.log("  MerkleStatementContract:", addrs.merkleStatementContract);

        console.log("\n1.6. Deploying FriStatementContract...");
        addrs.friStatementContract = address(new FriStatementContract());
        console.log("  FriStatementContract:", addrs.friStatementContract);

        // Step 2: Deploy CpuOods
        console.log("\n2. Deploying CpuOods...");
        addrs.oodsContract = address(new CpuOods());
        console.log("  CpuOods:", addrs.oodsContract);

        // Step 3: Deploy CpuConstraintPoly
        console.log("\n3. Deploying CpuConstraintPoly...");
        addrs.constraintPoly = address(new CpuConstraintPoly());
        console.log("  CpuConstraintPoly:", addrs.constraintPoly);

        // Step 4: Deploy Periodic Columns
        address[9] memory periodicColumns = _deployPeriodicColumns();

        // Step 5: Prepare aux polynomials array
        address[] memory auxPolynomials = _prepareAuxPolynomials(addrs.constraintPoly, periodicColumns);

        // Step 6: Deploy main CpuVerifier
        console.log("\n5. Deploying CpuVerifier...");
        addrs.verifier = address(new CpuVerifier(
            auxPolynomials,
            addrs.oodsContract,
            addrs.factRegistry,
            NUM_SECURITY_BITS,
            MIN_PROOF_OF_WORK_BITS
        ));
        console.log("  CpuVerifier:", addrs.verifier);

        // Step 7: Deploy CairoBootloaderProgram
        console.log("\n6. Deploying CairoBootloaderProgram...");
        addrs.bootloaderProgram = address(new CairoBootloaderProgram());
        console.log("  CairoBootloaderProgram:", addrs.bootloaderProgram);

        // Step 8: Deploy GpsStatementVerifier
        addrs.gpsVerifier = _deployGpsVerifier(addrs.bootloaderProgram, addrs.factRegistry, addrs.verifier);
    }

    function _deployPeriodicColumns() internal returns (address[9] memory periodicColumns) {
        console.log("\n4. Deploying Periodic Columns...");
        
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
    }

    function _prepareAuxPolynomials(
        address constraintPoly,
        address[9] memory periodicColumns
    ) internal pure returns (address[] memory auxPolynomials) {
        auxPolynomials = new address[](10);
        auxPolynomials[0] = constraintPoly;  // Index 0: CpuConstraintPoly
        for (uint256 i = 0; i < 9; i++) {
            auxPolynomials[i + 1] = periodicColumns[i];  // Indices 1-9: periodic columns
        }
    }

    function _deployGpsVerifier(
        address bootloaderProgram,
        address factRegistry,
        address verifier
    ) internal returns (address) {
        console.log("\n7. Deploying GpsStatementVerifier...");
        console.log("  CpuVerifier address:", verifier);
        
        // stark-evm-adapter uses hardcoded cairo_verifier_id = 6
        // So we need at least 7 verifiers (indices 0-6)
        // We'll use the same verifier for all indices
        address[] memory cairoVerifiers = new address[](7);
        console.log("  Created cairoVerifiers array with length:", cairoVerifiers.length);
        
        for (uint256 i = 0; i < 7; i++) {
            cairoVerifiers[i] = address(verifier);
            console.log("  Set cairoVerifiers[%s] to:", i, cairoVerifiers[i]);
        }

        // These values must match the bootloader config used when generating proofs
        uint256 simpleBootloaderProgramHash = 2837065596727015720211588542358388273918703458440061085859263118820688767610;
        uint256 hashedSupportedCairoVerifiers = 178987933271357263253427805726820412853545264541548426444153286928731358780;

        console.log("  Calling GpsStatementVerifier constructor with:");
        console.log("    bootloaderProgram:", bootloaderProgram);
        console.log("    factRegistry:", factRegistry);
        console.log("    cairoVerifiers.length:", cairoVerifiers.length);
        console.log("    cairoVerifiers[0]:", cairoVerifiers[0]);

        address gpsVerifier = address(new GpsStatementVerifier(
            bootloaderProgram,
            factRegistry,
            cairoVerifiers,
            hashedSupportedCairoVerifiers,
            simpleBootloaderProgramHash,
            address(0),  // referenceVerifier
            0            // referralDurationSeconds
        ));
        console.log("  GpsStatementVerifier deployed at:", gpsVerifier);
        
        // Verify the deployment by calling getCairoVerifierInfo if available
        GpsStatementVerifier gps = GpsStatementVerifier(gpsVerifier);
        try gps.getCairoVerifierInfo() returns (uint256 count, address firstVerifier) {
            console.log("  Verification: getCairoVerifierInfo() returned:");
            console.log("    count:", count);
            console.log("    firstVerifier:", firstVerifier);
            require(count > 0, "ERROR: GpsStatementVerifier was deployed with 0 Cairo verifiers!");
            require(firstVerifier == verifier, "ERROR: First verifier does not match expected verifier!");
        } catch {
            console.log("  Warning: getCairoVerifierInfo() not available (old contract version)");
        }
        
        return gpsVerifier;
    }

    function _saveDeploymentAddresses(DeploymentAddresses memory addrs) internal {
        console.log("\n===== DEPLOYMENT COMPLETE =====");
        console.log("\nDeployed Addresses:");
        console.log("  MemoryPageFactRegistry:", addrs.factRegistry);
        console.log("  MerkleStatementContract:", addrs.merkleStatementContract);
        console.log("  FriStatementContract:", addrs.friStatementContract);
        console.log("  CpuOods:", addrs.oodsContract);
        console.log("  CpuConstraintPoly:", addrs.constraintPoly);
        console.log("  CpuVerifier:", addrs.verifier);
        console.log("  CairoBootloaderProgram:", addrs.bootloaderProgram);
        console.log("  GpsStatementVerifier:", addrs.gpsVerifier);

        // Save to file for easy reference
        string memory deploymentInfo = string.concat(
            "{\n",
            '  "verifier": "', vm.toString(addrs.verifier), '",\n',
            '  "gpsVerifier": "', vm.toString(addrs.gpsVerifier), '",\n',
            '  "factRegistry": "', vm.toString(addrs.factRegistry), '",\n',
            '  "oodsContract": "', vm.toString(addrs.oodsContract), '",\n',
            '  "constraintPoly": "', vm.toString(addrs.constraintPoly), '",\n',
            '  "bootloaderProgram": "', vm.toString(addrs.bootloaderProgram), '",\n',
            '  "merkleStatementContract": "', vm.toString(addrs.merkleStatementContract), '",\n',
            '  "friStatementContract": "', vm.toString(addrs.friStatementContract), '"\n',
            "}\n"
        );

        vm.writeFile("deployment-addresses.json", deploymentInfo);
        console.log("\nAddresses saved to deployment-addresses.json");
    }
}
