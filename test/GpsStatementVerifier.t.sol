// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "../src/GpsStatementVerifier/GpsStatementVerifier.sol";
import "../src/layout_starknet/CpuVerifier.sol";
import "../src/common/MemoryPageFactRegistry.sol";
import "../src/layout_starknet/CpuOods.sol";
import "../src/layout_starknet/CpuConstraintPoly.sol";
import "../src/common/CairoBootloaderProgram.sol";
import "evm-verifier-columns/PedersenHashPointsXColumn.sol";
import "evm-verifier-columns/PedersenHashPointsYColumn.sol";
import "evm-verifier-columns/EcdsaPointsXColumn.sol";
import "evm-verifier-columns/EcdsaPointsYColumn.sol";
import "evm-verifier-columns/PoseidonPoseidonFullRoundKey0Column.sol";
import "evm-verifier-columns/PoseidonPoseidonFullRoundKey1Column.sol";
import "evm-verifier-columns/PoseidonPoseidonFullRoundKey2Column.sol";
import "evm-verifier-columns/PoseidonPoseidonPartialRoundKey0Column.sol";
import "evm-verifier-columns/PoseidonPoseidonPartialRoundKey1Column.sol";

contract GpsStatementVerifierTest is Test {
    using stdJson for string;

    GpsStatementVerifier public gpsVerifier;
    CpuVerifier public cpuVerifier;
    MemoryPageFactRegistry public factRegistry;
    CpuOods public oodsContract;
    CpuConstraintPoly public constraintPoly;
    CairoBootloaderProgram public bootloaderProgram;

    address[] public auxPolynomials;
    address[9] public periodicColumns;

    uint256 internal constant K_MODULUS = 0x800000000000011000000000000000000000000000000000000000000000001;

    function setUp() public {
        // Deploy MemoryPageFactRegistry
        factRegistry = new MemoryPageFactRegistry();

        // Deploy CpuOods
        oodsContract = new CpuOods();

        // Deploy CpuConstraintPoly
        constraintPoly = new CpuConstraintPoly();

        // Deploy periodic column contracts
        periodicColumns = [
            address(new PedersenHashPointsXColumn()),
            address(new PedersenHashPointsYColumn()),
            address(new EcdsaPointsXColumn()),
            address(new EcdsaPointsYColumn()),
            address(new PoseidonPoseidonFullRoundKey0Column()),
            address(new PoseidonPoseidonFullRoundKey1Column()),
            address(new PoseidonPoseidonFullRoundKey2Column()),
            address(new PoseidonPoseidonPartialRoundKey0Column()),
            address(new PoseidonPoseidonPartialRoundKey1Column())
        ];

        // Set up aux polynomials array
        auxPolynomials = new address[](10);
        auxPolynomials[0] = address(constraintPoly);
        for (uint256 i = 0; i < 9; i++) {
            auxPolynomials[i + 1] = periodicColumns[i];
        }

        // Deploy CpuVerifier
        cpuVerifier = new CpuVerifier(
            auxPolynomials,
            address(oodsContract),
            address(factRegistry),
            60,  // numSecurityBits
            20   // minProofOfWorkBits
        );

        // Deploy bootloader program
        bootloaderProgram = new CairoBootloaderProgram();

        // Deploy GPS Statement Verifier
        address[] memory cairoVerifiers = new address[](1);
        cairoVerifiers[0] = address(cpuVerifier);

        // Get simpleBootloaderProgramHash and hashedSupportedCairoVerifiers from bootloader_input.json
        // These values must match the bootloader config used when generating the proof
        uint256 simpleBootloaderProgramHash = 2837065596727015720211588542358388273918703458440061085859263118820688767610;
        uint256 hashedSupportedCairoVerifiers = 178987933271357263253427805726820412853545264541548426444153286928731358780;

        gpsVerifier = new GpsStatementVerifier(
            address(bootloaderProgram),
            address(factRegistry),
            cairoVerifiers,
            hashedSupportedCairoVerifiers,
            simpleBootloaderProgramHash,
            address(0),  // referenceVerifier
            0            // referralDurationSeconds
        );
    }

    /**
     * @notice Registers memory page facts using provided z and alpha values
     * @param inputJson The prepared input JSON string (for memory pairs data)
     * @param z The first interaction element
     * @param alpha The second interaction element
     */
    function registerMemoryPageFactsWithZAlpha(string memory inputJson, uint256 z, uint256 alpha) internal {
        // Parse regular page (page 0) - MUST exist for Cairo programs
        string memory regularPageKey = ".memory_page_facts.regular_page";
        string[] memory memoryPairsHex = vm.parseJsonStringArray(inputJson, string.concat(regularPageKey, ".memory_pairs"));
        require(memoryPairsHex.length > 0, "Regular page (page 0) must exist and have memory pairs");
        uint256[] memory memoryPairs = hexStringArrayToUint256Array(memoryPairsHex);
        factRegistry.registerRegularMemoryPage(memoryPairs, z, alpha, K_MODULUS);

        // Parse continuous pages (page > 0)
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

    /**
     * @notice Test GPS verifier with actual bootloader proof
     * @dev Verifies a real bootloader proof with fact topologies
     */
    function test_VerifyBootloaderProof() public {
        // Load bootloader proof data
        string memory inputJson = vm.readFile("./work/bootloader/input.json");
        require(bytes(inputJson).length > 0, "Bootloader input.json not found");

        // Parse proof data
        string[] memory proofParamsHex = vm.parseJsonStringArray(inputJson, ".proof_params");
        string[] memory proofHex = vm.parseJsonStringArray(inputJson, ".proof");
        string[] memory publicInputHex = vm.parseJsonStringArray(inputJson, ".public_input");

        // Convert to uint256 arrays
        uint256[] memory proofParams = hexStringArrayToUint256Array(proofParamsHex);
        uint256[] memory proof = hexStringArrayToUint256Array(proofHex);
        uint256[] memory publicInput = hexStringArrayToUint256Array(publicInputHex);

        // Get z and alpha from input
        string memory zHex = vm.parseJsonString(inputJson, ".z");
        string memory alphaHex = vm.parseJsonString(inputJson, ".alpha");
        uint256 z = hexStringToUint256(zHex);
        uint256 alpha = hexStringToUint256(alphaHex);

        // Register memory page facts first (like CpuVerifier does)
        registerMemoryPageFactsWithZAlpha(inputJson, z, alpha);

        // Create cairoAuxInput (public input + z + alpha)
        uint256[] memory cairoAuxInput = new uint256[](publicInput.length + 2);
        for (uint256 i = 0; i < publicInput.length; i++) {
            cairoAuxInput[i] = publicInput[i];
        }
        cairoAuxInput[publicInput.length] = z;
        cairoAuxInput[publicInput.length + 1] = alpha;

        // Parse taskMetadata from input.json (generated by prepare_input)
        string[] memory taskMetadataHex = vm.parseJsonStringArray(inputJson, ".task_metadata");
        uint256[] memory taskMetadata = hexStringArrayToUint256Array(taskMetadataHex);

        // Verify bootloader proof
        gpsVerifier.verifyProofAndRegister(
            proofParams,
            proof,
            taskMetadata,
            cairoAuxInput,
            0  // cairo verifier id
        );
    }

    // Helper functions from CpuVerifier.t.sol
    function hexStringToUint256(string memory hexString) internal pure returns (uint256) {
        bytes memory hexBytes = bytes(hexString);
        require(hexBytes.length > 0, "Empty hex string");

        uint256 start = 0;
        if (hexBytes.length >= 2 && hexBytes[0] == '0' && hexBytes[1] == 'x') {
            start = 2;
        }

        uint256 result = 0;
        for (uint256 i = start; i < hexBytes.length; i++) {
            uint8 digit = uint8(hexBytes[i]);
            uint8 value;

            if (digit >= 48 && digit <= 57) {
                value = digit - 48;
            } else if (digit >= 65 && digit <= 70) {
                value = digit - 55;
            } else if (digit >= 97 && digit <= 102) {
                value = digit - 87;
            } else {
                revert("Invalid hex character");
            }

            result = result * 16 + value;
        }

        return result;
    }

    function hexStringArrayToUint256Array(string[] memory hexArray) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](hexArray.length);
        for (uint256 i = 0; i < hexArray.length; i++) {
            result[i] = hexStringToUint256(hexArray[i]);
        }
        return result;
    }
}
