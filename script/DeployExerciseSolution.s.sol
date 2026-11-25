// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ExerciseSolution} from "../src/ExerciseSolution.sol";
import {Evaluator} from "../src/td/Evaluator.sol";
import {IExerciceSolution} from "../src/td/IExerciceSolution.sol";

/// @notice Déploie ExerciseSolution sur Sepolia puis le soumet à l'Evaluator.
/// Usage :
///   forge script script/DeployExerciseSolution.s.sol --rpc-url sepolia --account td-wallet --broadcast
contract DeployExerciseSolution is Script {
    address payable constant EVALUATOR = payable(0xa39ac9c5eF0582f5D0b21770e34c4c54d6e46Fa6);

    function run() external {
        vm.startBroadcast();

        // 1. Déploiement : le constructeur mint le token #1 à l'Evaluator
        ExerciseSolution solution = new ExerciseSolution(EVALUATOR);

        // 2. Enregistrement auprès de l'Evaluator (msg.sender = ton wallet)
        Evaluator(EVALUATOR).submitExercice(IExerciceSolution(address(solution)));

        vm.stopBroadcast();

        console.log("ExerciseSolution deployed at:", address(solution));
    }
}
