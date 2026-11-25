// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ExerciseSolution} from "../src/ExerciseSolution.sol";
import {AnimalBase} from "../src/AnimalBase.sol";
import {ERC20TD} from "../src/td/ERC20TD.sol";
import {Evaluator} from "../src/td/Evaluator.sol";
import {IExerciceSolution} from "../src/td/IExerciceSolution.sol";

/// @notice Rejoue en local le scénario du TD avec une copie de l'Evaluator,
/// pour valider le contrat avant de dépenser du gas sur Sepolia.
contract ExerciseSolutionTest is Test {
    ERC20TD points;
    Evaluator evaluator;
    address student = makeAddr("student");
    address stranger = makeAddr("stranger");

    function setUp() public {
        // On reproduit le déploiement du prof : token de points + Evaluator autorisé à minter
        points = new ERC20TD("TD-ERC721-101", "TD-ERC721-101", 0);
        evaluator = new Evaluator(points);
        points.setTeacher(address(evaluator), true);
        _fillRandomStore();
    }

    // ───────────────────────────── Helpers ─────────────────────────────

    /// @dev Le prof (ici ce contrat de test, "teacher" de l'ERC20) remplit la réserve d'animaux
    function _fillRandomStore() internal {
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
    }

    function _deployAndSubmit() internal returns (ExerciseSolution solution) {
        vm.startPrank(student);
        solution = new ExerciseSolution(address(evaluator));
        evaluator.submitExercice(IExerciceSolution(address(solution)));
        vm.stopPrank();
    }

    // ───────────────────────────── Ex1 ─────────────────────────────────

    function test_Token1BelongsToEvaluator() public {
        ExerciseSolution solution = _deployAndSubmit();
        assertEq(solution.ownerOf(1), address(evaluator));
        assertEq(solution.balanceOf(address(evaluator)), 1);
    }

    function test_SubmitGives4Points() public {
        _deployAndSubmit();
        assertEq(points.balanceOf(student), 4 ether); // 2 setup + 2 déploiement (18 décimales)
    }

    function test_Ex1GivesPoints() public {
        _deployAndSubmit();
        vm.prank(student);
        evaluator.ex1_testERC721();
        assertEq(points.balanceOf(student), 6 ether);
    }

    // ───────────────────────────── Ex2 ─────────────────────────────────

    /// @dev Scénario complet : ex2a -> lecture -> declare -> transfert -> ex2b
    function test_Ex2DeclaredAnimal() public {
        ExerciseSolution solution = _deployAndSubmit();

        vm.startPrank(student);
        evaluator.ex2a_getAnimalToCreateAttributes();
        string memory name = evaluator.readName(student);
        uint256 l = evaluator.readLegs(student);
        uint256 s = evaluator.readSex(student);
        bool w = evaluator.readWings(student);
        uint256 id = solution.declareAnimal(s, l, w, name);
        solution.transferFrom(student, address(evaluator), id);
        evaluator.ex2b_testDeclaredAnimal(id);
        vm.stopPrank();

        assertEq(id, 2);
        assertEq(points.balanceOf(student), 6 ether); // 4 (submit) + 2 (ex2b)
    }

    function test_DeclareAnimalStoresCharacteristics() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.prank(student);
        uint256 id = solution.declareAnimal(1, 4, true, "Pegase");

        (string memory n, bool w, uint256 l, uint256 s) = solution.getAnimalCharacteristics(id);
        assertEq(n, "Pegase");
        assertTrue(w);
        assertEq(l, 4);
        assertEq(s, 1);
        assertEq(solution.ownerOf(id), student);
    }

    // ───────────────────────────── Ex3 ─────────────────────────────────

    function test_DeployerIsBreeder() public {
        ExerciseSolution solution = _deployAndSubmit();
        assertTrue(solution.isBreeder(student));
        assertFalse(solution.isBreeder(stranger));
    }

    function test_NonBreederCannotDeclare() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.NotABreeder.selector, stranger));
        solution.declareAnimal(0, 4, false, "Intrus");
    }

    function test_RegisterRequiresExactPrice() public {
        ExerciseSolution solution = _deployAndSubmit();
        uint256 price = solution.registrationPrice();
        vm.deal(stranger, 1 ether);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.WrongRegistrationPayment.selector, price - 1, price));
        solution.registerMeAsBreeder{value: price - 1}();

        vm.prank(stranger);
        solution.registerMeAsBreeder{value: price}();
        assertTrue(solution.isBreeder(stranger));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.AlreadyBreeder.selector, stranger));
        solution.registerMeAsBreeder{value: price}();
    }

    function test_Ex3RegisterBreeder() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.deal(address(evaluator), 1 ether); // l'Evaluator paie son inscription avec son propre solde

        vm.prank(student);
        evaluator.ex3_testRegisterBreeder();

        assertTrue(solution.isBreeder(address(evaluator)));
        assertEq(address(solution).balance, solution.registrationPrice());
        assertEq(points.balanceOf(student), 6 ether); // 4 + 2
    }

    /// @dev Bonus : une fois l'Evaluator éleveur, ex4 passe avec le même contrat
    function test_Ex4DeclareAnimalAfterEx3() public {
        _deployAndSubmit();
        vm.deal(address(evaluator), 1 ether);

        vm.startPrank(student);
        evaluator.ex2a_getAnimalToCreateAttributes();
        evaluator.ex3_testRegisterBreeder();
        evaluator.ex4_testDeclareAnimal();
        vm.stopPrank();

        assertEq(points.balanceOf(student), 8 ether); // 4 + 2 (ex3) + 2 (ex4)
    }

    // ───────────────────────────── Ex5 ─────────────────────────────────

    /// @dev Scénario ex5 : l'Evaluator détient le token 1, l'étudiant détient un animal à lui
    function test_Ex5DeclareDeadAnimal() public {
        ExerciseSolution solution = _deployAndSubmit();

        vm.startPrank(student);
        solution.declareAnimal(0, 4, false, "Medor"); // l'étudiant doit détenir un animal
        evaluator.ex5_declareDeadAnimal();
        vm.stopPrank();

        assertEq(solution.balanceOf(address(evaluator)), 0);
        assertEq(points.balanceOf(student), 6 ether); // 4 + 2 (ex5)
    }

    function test_DeadAnimalIsBurnedAndReset() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.startPrank(student);
        uint256 id = solution.declareAnimal(1, 2, true, "Phenix");
        solution.declareDeadAnimal(id);
        vm.stopPrank();

        vm.expectRevert(); // ERC721NonexistentToken
        solution.ownerOf(id);
        (string memory n, bool w, uint256 l, uint256 s) = solution.getAnimalCharacteristics(id);
        assertEq(n, "");
        assertFalse(w);
        assertEq(l, 0);
        assertEq(s, 0);
        assertEq(solution.balanceOf(student), 0);
    }

    function test_CannotKillSomeoneElsesAnimal() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.prank(student);
        uint256 id = solution.declareAnimal(1, 2, true, "Phenix");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.NotAnimalOwner.selector, id, stranger));
        solution.declareDeadAnimal(id);
    }

    function test_EnumerableTracksOwnership() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.startPrank(student);
        uint256 a = solution.declareAnimal(0, 4, false, "A");
        uint256 b = solution.declareAnimal(0, 4, false, "B");
        solution.declareDeadAnimal(a);
        vm.stopPrank();

        assertEq(solution.tokenOfOwnerByIndex(student, 0), b);
        assertEq(solution.tokenOfOwnerByIndex(address(evaluator), 0), 1);
        assertEq(solution.totalSupply(), 2); // token 1 + animal B
    }

    // ───────────────────────────── Ex6 ─────────────────────────────────

    function test_Ex6aOfferForSale() public {
        ExerciseSolution solution = _deployAndSubmit(); // l'Evaluator détient le token 1
        vm.prank(student);
        evaluator.ex6a_auctionAnimal_offer();

        assertTrue(solution.isAnimalForSale(1));
        assertEq(solution.animalPrice(1), 0.0001 ether);
        assertEq(points.balanceOf(student), 5 ether); // 4 + 1 (ex6a)
    }

    function test_Ex6bBuyAnimal() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.deal(address(evaluator), 1 ether);

        vm.startPrank(student);
        uint256 id = solution.declareAnimal(0, 4, false, "A vendre");
        solution.offerForSale(id, 0.001 ether);
        uint256 before = student.balance;
        evaluator.ex6b_auctionAnimal_buy(id);
        vm.stopPrank();

        assertEq(solution.ownerOf(id), address(evaluator));
        assertEq(student.balance - before, 0.001 ether); // le vendeur est payé
        assertFalse(solution.isAnimalForSale(id)); // l'annonce disparaît après la vente
        assertEq(points.balanceOf(student), 6 ether); // 4 + 2 (ex6b)
    }

    function test_CannotOfferSomeoneElsesAnimal() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.NotAnimalOwner.selector, 1, stranger));
        solution.offerForSale(1, 1 ether);
    }

    function test_BuyRequiresExactPrice() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.prank(student);
        uint256 id = solution.declareAnimal(0, 4, false, "A");
        vm.prank(student);
        solution.offerForSale(id, 1 ether);

        vm.deal(stranger, 2 ether);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AnimalBase.WrongPayment.selector, 0.5 ether, 1 ether));
        solution.buyAnimal{value: 0.5 ether}(id);
    }

    function test_ListingClearedOnTransfer() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.startPrank(student);
        uint256 id = solution.declareAnimal(0, 4, false, "A");
        solution.offerForSale(id, 1 ether);
        solution.transferFrom(student, stranger, id);
        vm.stopPrank();

        assertFalse(solution.isAnimalForSale(id));
    }

    function test_OnlyOwnerCanWithdraw() public {
        ExerciseSolution solution = _deployAndSubmit();
        vm.deal(address(evaluator), 1 ether);
        vm.prank(student);
        evaluator.ex3_testRegisterBreeder();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        solution.withdraw();

        uint256 before = student.balance;
        vm.prank(student);
        solution.withdraw();
        assertEq(student.balance - before, solution.registrationPrice());
        assertEq(address(solution).balance, 0);
    }
}
