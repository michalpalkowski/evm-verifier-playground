// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../src/common/MemoryPageFactRegistry.sol";

contract RegisterMemoryFactsScript is Script {
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

    function run() external {
        // Load deployment addresses
        string memory deploymentJson = vm.readFile("deployment-addresses.json");
        address factRegistryAddress = deploymentJson.readAddress(".factRegistry");

        // Load and parse proof data
        string memory inputJson = vm.readFile("input.json");
        string memory zHex = vm.parseJsonString(inputJson, ".z");
        string memory alphaHex = vm.parseJsonString(inputJson, ".alpha");
        uint256 z = hexStringToUint256(zHex);
        uint256 alpha = hexStringToUint256(alphaHex);

        // Get private key for broadcasting
        string memory pkString = vm.envString("PRIVATE_KEY");
        if (bytes(pkString).length <= 2 || bytes(pkString)[0] != "0" || bytes(pkString)[1] != "x") {
            pkString = string(abi.encodePacked("0x", pkString));
        }
        uint256 deployerPrivateKey = vm.parseUint(pkString);
        address sender = vm.addr(deployerPrivateKey);

        console.log("\n=== Registering Memory Page Facts on Sepolia ===");
        console.log("Sender:", sender);
        console.log("Fact Registry:", factRegistryAddress);
        console.log("z:");
        console.logBytes32(bytes32(z));
        console.log("alpha:");
        console.logBytes32(bytes32(alpha));

        vm.startBroadcast(deployerPrivateKey);

        // Register memory page facts
        console.log("\n=== Registering Regular Page (Page 0) ===");
        registerRegularPage(inputJson, z, alpha, factRegistryAddress);
        console.log("Regular page registered");

        console.log("\n=== Registering Continuous Pages ===");
        registerContinuousPages(inputJson, z, alpha, factRegistryAddress);
        console.log("Continuous pages registered");

        vm.stopBroadcast();

        console.log("\n=== Memory Page Facts Registration Complete ===");
        console.log("Now you can run: make verify-proof-sepolia-only");
    }
}

