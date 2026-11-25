// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AnimalBase} from "./AnimalBase.sol";

/// @title ExerciseSolution2 - contrat évalué par Evaluator2 (ex7a, ex7b, ex7c)
/// @notice Socle AnimalBase + généalogie (parents) + location des services de reproduction.
/// @dev Règle de reproduction : pour utiliser un animal comme parent, l'appelant doit
///      soit en être propriétaire, soit avoir payé un droit de reproduction (usage unique).
contract ExerciseSolution2 is AnimalBase {
    struct Parents {
        uint256 parent1;
        uint256 parent2;
    }

    /// @dev tokenId => ses deux parents (0, 0 si l'animal n'a pas de parents déclarés)
    mapping(uint256 => Parents) private _parents;

    /// @dev tokenId => prix d'une reproduction en wei. 0 = pas proposé à la reproduction.
    mapping(uint256 => uint256) private _reproductionPrices;

    /// @notice tokenId => éleveur ayant payé le droit d'utiliser cet animal comme parent (une fois)
    mapping(uint256 => address) public authorizedBreederToReproduce;

    event AnimalBred(uint256 indexed animalNumber, uint256 indexed parent1, uint256 indexed parent2);
    event AnimalOfferedForReproduction(uint256 indexed animalNumber, uint256 price);
    event ReproductionPaid(uint256 indexed animalNumber, address indexed breeder, uint256 price);

    error SameParents(uint256 animalNumber);
    error NotAllowedToBreed(uint256 animalNumber, address caller);
    error NotOfferedForReproduction(uint256 animalNumber);
    error ReproductionAlreadyReserved(uint256 animalNumber, address breeder);

    constructor(address evaluator) AnimalBase(evaluator) {}

    // ───────────────────────────── Généalogie (ex7a) ────────────────────────────

    /// @notice Crée un animal en déclarant ses deux parents. Réservé aux éleveurs.
    function declareAnimalWithParents(
        uint256 sex,
        uint256 legs,
        bool wings,
        string calldata name,
        uint256 parent1,
        uint256 parent2
    ) external onlyBreeder returns (uint256 id) {
        if (parent1 == parent2) revert SameParents(parent1);
        _useAsParent(parent1);
        _useAsParent(parent2);

        id = _createAnimal(msg.sender, sex, legs, wings, name);
        _parents[id] = Parents(parent1, parent2);
        emit AnimalBred(id, parent1, parent2);
    }

    /// @notice Renvoie les deux parents d'un animal.
    function getParents(uint256 animalNumber) external view returns (uint256, uint256) {
        Parents storage p = _parents[animalNumber];
        return (p.parent1, p.parent2);
    }

    // ───────────────────────────── Reproduction (ex7b, ex7c) ────────────────────

    /// @notice Propose un animal à la reproduction contre paiement. Propriétaire uniquement.
    /// @return L'identifiant de l'animal proposé
    function offerForReproduction(uint256 animalNumber, uint256 priceOfReproduction)
        external
        onlyAnimalOwner(animalNumber)
        returns (uint256)
    {
        if (priceOfReproduction == 0) revert ZeroPrice();
        _reproductionPrices[animalNumber] = priceOfReproduction;
        emit AnimalOfferedForReproduction(animalNumber, priceOfReproduction);
        return animalNumber;
    }

    /// @notice Indique si un animal est proposé à la reproduction.
    function canReproduce(uint256 animalNumber) external view returns (bool) {
        return _reproductionPrices[animalNumber] != 0;
    }

    /// @notice Prix d'une reproduction avec cet animal (0 s'il n'est pas proposé).
    function reproductionPrice(uint256 animalNumber) external view returns (uint256) {
        return _reproductionPrices[animalNumber];
    }

    /// @notice Paie le droit d'utiliser un animal comme parent pour UNE reproduction.
    function payForReproduction(uint256 animalNumber) external payable {
        uint256 price = _reproductionPrices[animalNumber];
        if (price == 0) revert NotOfferedForReproduction(animalNumber);
        if (msg.value != price) revert WrongPayment(msg.value, price);

        // Un seul droit en attente à la fois : sinon un 2e payeur écraserait le 1er,
        // qui perdrait son paiement sans pouvoir se reproduire.
        address current = authorizedBreederToReproduce[animalNumber];
        if (current != address(0)) revert ReproductionAlreadyReserved(animalNumber, current);

        // Effets avant interactions
        authorizedBreederToReproduce[animalNumber] = msg.sender;
        _pay(ownerOf(animalNumber), price);

        emit ReproductionPaid(animalNumber, msg.sender, price);
    }

    // ───────────────────────────── Internes ─────────────────────────────────────

    /// @dev Vérifie le droit d'utiliser `parent` et consomme le droit payé s'il y a lieu.
    function _useAsParent(uint256 parent) private {
        if (ownerOf(parent) == msg.sender) return; // ownerOf revert si le parent n'existe pas
        if (authorizedBreederToReproduce[parent] != msg.sender) revert NotAllowedToBreed(parent, msg.sender);
        delete authorizedBreederToReproduce[parent]; // droit à usage unique
    }

    /// @dev Changement de propriétaire (transfert, burn) : l'offre et le droit en attente
    ///      tombent, le nouveau propriétaire n'a consenti à rien.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        delete _reproductionPrices[tokenId];
        delete authorizedBreederToReproduce[tokenId];
        return super._update(to, tokenId, auth);
    }
}
