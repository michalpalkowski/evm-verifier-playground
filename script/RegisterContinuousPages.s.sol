// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../src/common/MemoryPageFactRegistry.sol";

contract RegisterContinuousPagesScript is Script {
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

    function registerSingleContinuousPage(
        string memory inputJson,
        uint256 pageIndex,
        uint256 z,
        uint256 alpha,
        address factRegistryAddress
    ) internal returns (bool) {
        string memory continuousPagesKey = ".memory_page_facts.continuous_pages";
        string memory pageKey = string.concat(continuousPagesKey, "[", vm.toString(pageIndex), "]");
        
        try vm.parseJsonString(inputJson, string.concat(pageKey, ".start_addr")) returns (string memory startAddrHex) {
            string[] memory valuesHex = vm.parseJsonStringArray(inputJson, string.concat(pageKey, ".values"));
            uint256 startAddr = hexStringToUint256(startAddrHex);
            uint256[] memory values = hexStringArrayToUint256Array(valuesHex);
            
            MemoryPageFactRegistry factRegistry = MemoryPageFactRegistry(factRegistryAddress);
            console.log("Registering continuous page", pageIndex, "at address", startAddr);
            factRegistry.registerContinuousMemoryPage(startAddr, values, z, alpha, K_MODULUS);
            return true;
        } catch {
            return false;
        }
    }

    function registerAllContinuousPages(string memory inputJson, uint256 z, uint256 alpha, address factRegistryAddress) internal returns (uint256) {
        uint256 i = 0;
        uint256 registered = 0;
        
        while (true) {
            if (registerSingleContinuousPage(inputJson, i, z, alpha, factRegistryAddress)) {
                registered++;
                i++;
            } else {
                break;
            }
        }
        
        return registered;
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

        console.log("\n=== Registering Continuous Pages on Sepolia ===");
        console.log("Sender:", sender);
        console.log("Fact Registry:", factRegistryAddress);
        console.log("z:");
        console.logBytes32(bytes32(z));
        console.log("alpha:");
        console.logBytes32(bytes32(alpha));

        vm.startBroadcast(deployerPrivateKey);

        uint256 registered = registerAllContinuousPages(inputJson, z, alpha, factRegistryAddress);

        vm.stopBroadcast();

        console.log("\n=== Continuous Pages Registration Complete ===");
        console.log("Registered", registered, "continuous pages");
        console.log("Note: Regular page (page 0) will be registered by verifyProofAndRegister");
    }
}

