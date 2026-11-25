// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExerciseSolution2} from "../src/ExerciseSolution2.sol";
import {AnimalBase} from "../src/AnimalBase.sol";
import {ERC20TD} from "../src/td/ERC20TD.sol";
import {Evaluator2} from "../src/td/Evaluator2.sol";
import {IExerciceSolution} from "../src/td/IExerciceSolution.sol";

/// @notice Rejoue en local le scénario d'Evaluator2 (ex7a, ex7b, ex7c).
contract ExerciseSolution2Test is Test {
    ERC20TD points;
    Evaluator2 evaluator;
    ExerciseSolution2 solution;
    address student = makeAddr("student");
    address stranger = makeAddr("stranger");

    function setUp() public {
        points = new ERC20TD("TD-ERC721-101", "TD-ERC721-101", 0);
        evaluator = new Evaluator2(points);
        points.setTeacher(address(evaluator), true);

        string[20] memory names;
        uint256[20] memory legs;
        uint256[20] memory sexes;
        bool[20] memory wings;
        for (uint256 i = 0; i < 20; i++) {
            names[i] = string.concat("Animal", vm.toString(i));
            legs[i] = i % 5;
            sexes[i] = i % 2;
            wings[i] = i % 3 == 0;
        }
        evaluator.setRandomValuesStore(names, legs, sexes, wings);

        // Même séquence que le script de déploiement
        vm.startPrank(student);
        solution = new ExerciseSolution2(address(evaluator)); // token 1 -> Evaluator2
        solution.addBreeder(address(evaluator)); // Evaluator2 ne s'inscrit jamais lui-même
        evaluator.submitExercice(IExerciceSolution(address(solution)));
        vm.stopPrank();
    }

    /// @dev ex7a : l'Evaluator crée un animal à partir de deux parents qu'il possède
    function _ex7a() internal {
        vm.startPrank(student);
        uint256 parent2 = solution.declareAnimal(1, 4, false, "Parent2"); // id 2
        solution.transferFrom(student, address(evaluator), parent2);
        evaluator.ex7a_breedAnimalWithParents(1, parent2); // enfant = id 3
        vm.stopPrank();
    }

    function test_Ex7a() public {
        _ex7a();
        (uint256 p1, uint256 p2) = solution.getParents(3);
        assertEq(p1, 1);
        assertEq(p2, 2);
        assertEq(solution.ownerOf(3), address(evaluator));
        assertEq(points.balanceOf(student), 1 ether);
    }

    function test_Ex7b() public {
        vm.startPrank(student);
        solution.declareAnimal(0, 4, false, "Mien"); // l'étudiant doit détenir un animal
        evaluator.ex7b_offerAnimalForReproduction();
        vm.stopPrank();

        assertTrue(solution.canReproduce(1));
        assertEq(solution.reproductionPrice(1), 0.0001 ether);
        assertEq(points.balanceOf(student), 1 ether);
    }

    function test_Ex7c() public {
        vm.deal(address(evaluator), 1 ether);
        vm.startPrank(student);
        uint256 stud = solution.declareAnimal(0, 4, false, "Etalon");
        solution.offerForReproduction(stud, 0.0001 ether);
        uint256 before = student.balance;
        evaluator.ex7c_payForReproduction(stud);
        vm.stopPrank();

        assertEq(student.balance - before, 0.0001 ether); // le propriétaire est payé
        assertEq(solution.authorizedBreederToReproduce(stud), address(0)); // droit consommé
        assertEq(points.balanceOf(student), 2 ether); // ex7c + ex7a (appelé en interne)
    }

    function test_FullScenarioGives3Points() public {
        vm.deal(address(evaluator), 1 ether);
        _ex7a(); // ids 2 (parent), 3 (enfant)
        vm.startPrank(student);
        uint256 mine = solution.declareAnimal(0, 4, false, "Mien"); // id 4
        evaluator.ex7b_offerAnimalForReproduction();
        solution.offerForReproduction(mine, 0.0001 ether);
        evaluator.ex7c_payForReproduction(mine);
        vm.stopPrank();
        assertEq(points.balanceOf(student), 3 ether);
    }

    // ───────────────────────────── Règles métier ─────────────────────────────

    function test_CannotBreedWithoutRights() public {
        vm.startPrank(student);
        uint256 a = solution.declareAnimal(0, 4, false, "A");
        vm.stopPrank();
        // stranger devient éleveur mais ne possède pas l'animal 1 (Evaluator) ni l'animal a
        vm.prank(student);
        solution.addBreeder(stranger);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ExerciseSolution2.NotAllowedToBreed.selector, 1, stranger));
        solution.declareAnimalWithParents(0, 4, false, "Bebe", 1, a);
    }

    function test_SameParentsRejected() public {
        vm.startPrank(student);
        uint256 a = solution.declareAnimal(0, 4, false, "A");
        vm.expectRevert(abi.encodeWithSelector(ExerciseSolution2.SameParents.selector, a));
        solution.declareAnimalWithParents(0, 4, false, "Clone", a, a);
        vm.stopPrank();
    }

    function test_ReproductionRightIsSingleUse() public {
        vm.prank(student);
        uint256 stud = solution.declareAnimal(0, 4, false, "Etalon");
        vm.prank(student);
        solution.offerForReproduction(stud, 1 ether);

        vm.prank(student);
        solution.addBreeder(stranger);
        vm.startPrank(stranger);
        uint256 own1 = solution.declareAnimal(1, 4, false, "S1");
        vm.deal(stranger, 2 ether);
        solution.payForReproduction{value: 1 ether}(stud);
        solution.declareAnimalWithParents(0, 4, false, "Bebe", own1, stud); // OK
        vm.expectRevert(abi.encodeWithSelector(ExerciseSolution2.NotAllowedToBreed.selector, stud, stranger));
        solution.declareAnimalWithParents(0, 4, false, "Bebe2", own1, stud); // droit consommé
        vm.stopPrank();
    }

    function test_SecondPayerCannotOverwriteReservation() public {
        vm.prank(student);
        uint256 stud = solution.declareAnimal(0, 4, false, "Etalon");
        vm.prank(student);
        solution.offerForReproduction(stud, 1 ether);

        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        solution.payForReproduction{value: 1 ether}(stud);

        address other = makeAddr("other");
        vm.deal(other, 1 ether);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(ExerciseSolution2.ReproductionAlreadyReserved.selector, stud, stranger));
        solution.payForReproduction{value: 1 ether}(stud);
    }

    function test_CannotOfferSomeoneElsesAnimal() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.NotAnimalOwner.selector, 1, stranger));
        solution.offerForReproduction(1, 1 ether);
    }

    function test_OfferClearedOnTransfer() public {
        vm.startPrank(student);
        uint256 a = solution.declareAnimal(0, 4, false, "A");
        solution.offerForReproduction(a, 1 ether);
        solution.transferFrom(student, stranger, a);
        vm.stopPrank();
        assertFalse(solution.canReproduce(a));
    }
}
