// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../src/layout_starknet/CpuVerifier.sol";
import "../src/common/MemoryPageFactRegistry.sol";

contract VerifyProofScript is Script {
    using stdJson for string;

    uint256 constant K_MODULUS = 0x800000000000011000000000000000000000000000000000000000000000001;

    // Helper function to convert hex string to uint256
    function hexStringToUint256(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        require(b.length >= 2 && b[0] == "0" && b[1] == "x", "Invalid hex string");

        uint256 result = 0;
        for (uint256 i = 2; i < b.length; i++) {
            result = result * 16;
            uint8 digit = uint8(b[i]);
            if (digit >= 48 && digit <= 57) {
                result += digit - 48;
            } else if (digit >= 97 && digit <= 102) {
                result += digit - 87;
            } else if (digit >= 65 && digit <= 70) {
                result += digit - 55;
            }
        }
        return result;
    }

    // Helper function to convert hex string array to uint256 array
    function hexStringArrayToUint256Array(string[] memory hexStrings)
        internal pure returns (uint256[] memory)
    {
        uint256[] memory result = new uint256[](hexStrings.length);
        for (uint256 i = 0; i < hexStrings.length; i++) {
            result[i] = hexStringToUint256(hexStrings[i]);
        }
        return result;
    }

    function registerRegularPage(
        string memory inputJson,
        uint256 z,
        uint256 alpha,
        MemoryPageFactRegistry factRegistry
    ) internal {
        string[] memory memoryPairsHex = vm.parseJsonStringArray(
            inputJson,
            ".memory_page_facts.regular_page.memory_pairs"
        );
        require(memoryPairsHex.length > 0, "Regular page must exist");
        uint256[] memory memoryPairs = hexStringArrayToUint256Array(memoryPairsHex);

        console.log("Registering regular page with", memoryPairs.length, "pairs");
        factRegistry.registerRegularMemoryPage(memoryPairs, z, alpha, K_MODULUS);
    }

    function registerContinuousPages(
        string memory inputJson,
        uint256 z,
        uint256 alpha,
        MemoryPageFactRegistry factRegistry
    ) internal {
        uint256 pageCount = 0;
        for (uint256 i = 0; i < 100; i++) {
            string memory addrPath = string.concat(
                ".memory_page_facts.continuous_pages[",
                vm.toString(i),
                "].start_addr"
            );

            try vm.parseJsonString(inputJson, addrPath) returns (string memory startAddrHex) {
                string memory valuesPath = string.concat(
                    ".memory_page_facts.continuous_pages[",
                    vm.toString(i),
                    "].values"
                );
                string[] memory valuesHex = vm.parseJsonStringArray(inputJson, valuesPath);

                uint256 startAddr = hexStringToUint256(startAddrHex);
                uint256[] memory values = hexStringArrayToUint256Array(valuesHex);

                factRegistry.registerContinuousMemoryPage(startAddr, values, z, alpha, K_MODULUS);
                pageCount++;
            } catch {
                break;
            }
        }
        console.log("Registered", pageCount, "continuous pages");
    }

    function run() external {
        // Load deployment addresses
        string memory deploymentJson = vm.readFile("deployment-addresses.json");
        address verifierAddress = deploymentJson.readAddress(".verifier");
        address factRegistryAddress = deploymentJson.readAddress(".factRegistry");

        console.log("Using verifier at:", verifierAddress);
        console.log("Using factRegistry at:", factRegistryAddress);

        // Load proof data
        string memory inputJson = vm.readFile("input.json");

        // Parse proof params
        uint256[] memory proofParams = inputJson.readUintArray(".proof_params");
        console.log("Proof params length:", proofParams.length);

        // Parse proof
        uint256[] memory proof = inputJson.readUintArray(".proof");
        console.log("Proof length:", proof.length);

        // Parse public input
        uint256[] memory publicInput = inputJson.readUintArray(".public_input");
        console.log("Public input length:", publicInput.length);

        // Parse z and alpha
        uint256 z = hexStringToUint256(inputJson.readString(".z"));
        uint256 alpha = hexStringToUint256(inputJson.readString(".alpha"));

        // Get private key for broadcasting (add 0x prefix if needed)
        string memory pkString = vm.envString("PRIVATE_KEY");
        if (bytes(pkString).length > 2 && bytes(pkString)[0] == "0" && bytes(pkString)[1] == "x") {
            // Already has 0x prefix
        } else {
            // Add 0x prefix
            pkString = string(abi.encodePacked("0x", pkString));
        }
        uint256 deployerPrivateKey = vm.parseUint(pkString);
        address sender = vm.addr(deployerPrivateKey);

        console.log("\n=== Verifying Proof on Sepolia ===");
        console.log("Sender:", sender);
        console.log("Verifier:", verifierAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Register memory page facts first
        console.log("\n=== Registering Memory Page Facts ===");
        console.log("z:");
        console.logBytes32(bytes32(z));
        console.log("alpha:");
        console.logBytes32(bytes32(alpha));

        MemoryPageFactRegistry factRegistry = MemoryPageFactRegistry(factRegistryAddress);
        registerRegularPage(inputJson, z, alpha, factRegistry);
        registerContinuousPages(inputJson, z, alpha, factRegistry);

        // Create verifier instance
        CpuVerifier verifier = CpuVerifier(verifierAddress);

        // Verify proof
        console.log("\n=== Calling verifyProofExternal ===");
        try verifier.verifyProofExternal(proofParams, proof, publicInput) {
            console.log("\n SUCCESS: Proof verified on-chain!");
        } catch Error(string memory reason) {
            console.log("\n FAILED: Proof verification failed");
            console.log("Reason:", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("\n FAILED: Proof verification failed (low-level error)");
            revert("Verification failed");
        }

        vm.stopBroadcast();

        console.log("\n=== Verification Complete ===");
    }
}
