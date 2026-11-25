// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ExerciseSolution2} from "../src/ExerciseSolution2.sol";
import {Evaluator2} from "../src/td/Evaluator2.sol";
import {IExerciceSolution} from "../src/td/IExerciceSolution.sol";

/// @notice Déploie ExerciseSolution2 sur Sepolia, inscrit Evaluator2 comme éleveur, soumet,
///         puis valide ex7a, ex7b et ex7c.
/// Usage :
///   forge script script/DeployExerciseSolution2.s.sol --rpc-url sepolia --account td-wallet \
///     --sender 0x50318E83E291E89A4641CeC9523d7e11783000fE --broadcast --slow \
///     --gas-estimate-multiplier 120 --with-gas-price 0.002gwei --priority-gas-price 0.001gwei
/// --sender : adresse de td-wallet. --slow : attend chaque confirmation.
/// --gas-estimate-multiplier 120 : avec la marge par défaut (130 %), le déploiement demande
/// 17,2M gas et dépasse la limite de 16,7M gas par transaction.
contract DeployExerciseSolution2 is Script {
    address payable constant EVALUATOR2 = payable(0xB6C6cf310456Bd0dEE01162A9150EC7ccA146936);

    function run() external {
        vm.startBroadcast();

        // 1. Déploiement : le constructeur mint le token #1 à Evaluator2
        ExerciseSolution2 solution = new ExerciseSolution2(EVALUATOR2);

        // 2. Evaluator2 n'appelle jamais registerMeAsBreeder : on l'inscrit nous-mêmes
        solution.addBreeder(EVALUATOR2);

        // 3. Enregistrement auprès d'Evaluator2 (msg.sender = ton wallet)
        Evaluator2(EVALUATOR2).submitExercice(IExerciceSolution(address(solution)));

        // 4. Notre propre animal : requis par ex7b (on doit en détenir un), puis loué dans ex7c.
        //    Caractéristiques libres, Evaluator2 ne vérifie que l'animal qu'il crée lui-même.
        uint256 mine = solution.declareAnimal(0, 4, false, "Etalon");

        // 5. ex7b : Evaluator2 propose son token 1 à la reproduction (1 pt)
        Evaluator2(EVALUATOR2).ex7b_offerAnimalForReproduction();

        // 6. ex7c : Evaluator2 paie pour notre animal puis se reproduit avec (1 pt).
        //    Cet appel exécute aussi ex7a en interne (1 pt).
        solution.offerForReproduction(mine, 0.0001 ether);
        Evaluator2(EVALUATOR2).ex7c_payForReproduction(mine);

        vm.stopBroadcast();

        console.log("ExerciseSolution2 deployed at:", address(solution));

        // Vérifié pendant la simulation : si un exercice manque, rien n'est diffusé.
        require(Evaluator2(EVALUATOR2).exerciceProgression(msg.sender, 71), "ex7a non valide");
        require(Evaluator2(EVALUATOR2).exerciceProgression(msg.sender, 72), "ex7b non valide");
        require(Evaluator2(EVALUATOR2).exerciceProgression(msg.sender, 73), "ex7c non valide");
        console.log("ex7a, ex7b, ex7c valides pour:", msg.sender);
    }
}
