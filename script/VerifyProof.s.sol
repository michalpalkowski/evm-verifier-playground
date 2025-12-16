// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../src/GpsStatementVerifier/GpsStatementVerifier.sol";
import "../src/common/MemoryPageFactRegistry.sol";

contract VerifyProofScript is Script {
    using stdJson for string;

    uint256 internal constant K_MODULUS = 0x800000000000011000000000000000000000000000000000000000000000001;

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

    function loadGpsVerifierAddress(string memory deploymentJson) internal view returns (address) {
        // Check if gpsVerifier exists in JSON
        try vm.parseJsonString(deploymentJson, ".gpsVerifier") returns (string memory) {
            return deploymentJson.readAddress(".gpsVerifier");
        } catch {
            // Fallback: check for verifier (for backward compatibility)
            try vm.parseJsonString(deploymentJson, ".verifier") returns (string memory) {
                console.log("Warning: Using CpuVerifier instead of GpsStatementVerifier");
                console.log("For bootloader proofs, deploy GpsStatementVerifier");
                address verifierAddr = deploymentJson.readAddress(".verifier");
                console.log("CpuVerifier at:", verifierAddr);
                revert("Please deploy GpsStatementVerifier for bootloader proof verification");
            } catch {
                revert("No verifier address found in deployment-addresses.json");
            }
        }
    }

    function parseInputJson(string memory inputJson) 
        internal 
        view 
        returns (
            uint256[] memory proofParams,
            uint256[] memory proof,
            uint256[] memory publicInput,
            uint256 z,
            uint256 alpha,
            uint256[] memory taskMetadata
        ) 
    {
        // Parse proof params
        string[] memory proofParamsHex = vm.parseJsonStringArray(inputJson, ".proof_params");
        proofParams = hexStringArrayToUint256Array(proofParamsHex);

        // Parse proof
        string[] memory proofHex = vm.parseJsonStringArray(inputJson, ".proof");
        proof = hexStringArrayToUint256Array(proofHex);

        // Parse public input
        string[] memory publicInputHex = vm.parseJsonStringArray(inputJson, ".public_input");
        publicInput = hexStringArrayToUint256Array(publicInputHex);

        // Parse z and alpha
        string memory zHex = vm.parseJsonString(inputJson, ".z");
        string memory alphaHex = vm.parseJsonString(inputJson, ".alpha");
        z = hexStringToUint256(zHex);
        alpha = hexStringToUint256(alphaHex);

        // Parse taskMetadata
        string[] memory taskMetadataHex = vm.parseJsonStringArray(inputJson, ".task_metadata");
        taskMetadata = hexStringArrayToUint256Array(taskMetadataHex);
    }

    function createCairoAuxInput(uint256[] memory publicInput, uint256 z, uint256 alpha)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory cairoAuxInput = new uint256[](publicInput.length + 2);
        for (uint256 i = 0; i < publicInput.length; i++) {
            cairoAuxInput[i] = publicInput[i];
        }
        cairoAuxInput[publicInput.length] = z;
        cairoAuxInput[publicInput.length + 1] = alpha;
        return cairoAuxInput;
    }

    function registerRegularPage(string memory inputJson, uint256 z, uint256 alpha, address factRegistryAddress) internal {
        MemoryPageFactRegistry factRegistry = MemoryPageFactRegistry(factRegistryAddress);
        string memory regularPageKey = ".memory_page_facts.regular_page";
        string[] memory memoryPairsHex = vm.parseJsonStringArray(inputJson, string.concat(regularPageKey, ".memory_pairs"));
        require(memoryPairsHex.length > 0, "Regular page (page 0) must exist and have memory pairs");
        uint256[] memory memoryPairs = hexStringArrayToUint256Array(memoryPairsHex);
        factRegistry.registerRegularMemoryPage(memoryPairs, z, alpha, K_MODULUS);
    }

    function registerContinuousPages(string memory inputJson, uint256 z, uint256 alpha, address factRegistryAddress) internal {
        MemoryPageFactRegistry factRegistry = MemoryPageFactRegistry(factRegistryAddress);
        string memory continuousPagesKey = ".memory_page_facts.continuous_pages";
        uint256 i = 0;
        while (true) {
            string memory pageKey = string.concat(continuousPagesKey, "[", vm.toString(i), "]");
            try vm.parseJsonString(inputJson, string.concat(pageKey, ".start_addr")) returns (string memory startAddrHex) {
                string[] memory valuesHex = vm.parseJsonStringArray(inputJson, string.concat(pageKey, ".values"));
                uint256 startAddr = hexStringToUint256(startAddrHex);
                uint256[] memory values = hexStringArrayToUint256Array(valuesHex);
                factRegistry.registerContinuousMemoryPage(startAddr, values, z, alpha, K_MODULUS);
                i++;
            } catch {
                break;
            }
        }
    }

    function registerMemoryPageFacts(string memory inputJson, uint256 z, uint256 alpha, address factRegistryAddress) internal {
        registerRegularPage(inputJson, z, alpha, factRegistryAddress);
        registerContinuousPages(inputJson, z, alpha, factRegistryAddress);
    }

    function run() external {
        // Load deployment addresses
        string memory deploymentJson = vm.readFile("deployment-addresses.json");
        address gpsVerifierAddress = loadGpsVerifierAddress(deploymentJson);
        address factRegistryAddress = deploymentJson.readAddress(".factRegistry");

        // Load and parse proof data
        string memory inputJson = vm.readFile("input.json");
        (
            uint256[] memory proofParams,
            uint256[] memory proof,
            uint256[] memory publicInput,
            uint256 z,
            uint256 alpha,
            uint256[] memory taskMetadata
        ) = parseInputJson(inputJson);

        console.log("Proof params length:", proofParams.length);
        console.log("Proof length:", proof.length);
        console.log("Public input length:", publicInput.length);
        console.log("Task metadata length:", taskMetadata.length);

        // Create cairoAuxInput (public input + z + alpha)
        uint256[] memory cairoAuxInput = createCairoAuxInput(publicInput, z, alpha);

        // Get private key for broadcasting
        string memory pkString = vm.envString("PRIVATE_KEY");
        if (bytes(pkString).length <= 2 || bytes(pkString)[0] != "0" || bytes(pkString)[1] != "x") {
            pkString = string(abi.encodePacked("0x", pkString));
        }
        uint256 deployerPrivateKey = vm.parseUint(pkString);
        address sender = vm.addr(deployerPrivateKey);

        console.log("\n=== Verifying Proof on Sepolia ===");
        console.log("Sender:", sender);
        console.log("GPS Verifier:", gpsVerifierAddress);
        console.log("z:");
        console.logBytes32(bytes32(z));
        console.log("alpha:");
        console.logBytes32(bytes32(alpha));

        vm.startBroadcast(deployerPrivateKey);

        // Note: Memory page facts should be registered separately using RegisterMemoryFacts.s.sol
        // if the transaction is too large. For smaller proofs, we can register them here.
        // Uncomment the following lines if you want to register facts in the same transaction:
        // console.log("\n=== Registering Memory Page Facts ===");
        // registerMemoryPageFacts(inputJson, z, alpha, factRegistryAddress);
        // console.log("Memory page facts registered");

        // Create GPS verifier instance and verify
        GpsStatementVerifier gpsVerifier = GpsStatementVerifier(gpsVerifierAddress);

        // Verify proof using verifyProofAndRegister
        console.log("\n=== Calling verifyProofAndRegister ===");
        try gpsVerifier.verifyProofAndRegister(
            proofParams,
            proof,
            taskMetadata,
            cairoAuxInput,
            0  // cairo verifier id
        ) {
            console.log("\nSUCCESS: Proof verified and facts registered on-chain!");
        } catch Error(string memory reason) {
            console.log("\nFAILED: Proof verification failed");
            console.log("Reason:", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("\nFAILED: Proof verification failed (low-level error)");
            revert("Verification failed");
        }

        vm.stopBroadcast();

        console.log("\n=== Verification Complete ===");
    }
}
