// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AnimalBase} from "./AnimalBase.sol";

/// @title ExerciseSolution - contrat évalué par Evaluator (ex1 à ex6)
/// @notice Socle AnimalBase + place de marché pour vendre/acheter des animaux.
contract ExerciseSolution is AnimalBase {
    /// @dev tokenId => prix de vente en wei. 0 = pas en vente.
    mapping(uint256 => uint256) private _salePrices;

    event AnimalOfferedForSale(uint256 indexed animalNumber, uint256 price);
    event AnimalSold(uint256 indexed animalNumber, address indexed seller, address indexed buyer, uint256 price);

    error AnimalNotForSale(uint256 animalNumber);

    constructor(address evaluator) AnimalBase(evaluator) {}

    // ───────────────────────────── Vente (ex6) ──────────────────────────────────

    /// @notice Met un animal en vente. Seul son propriétaire peut le faire.
    /// @param price Prix en wei, strictement positif (0 signifie "pas en vente")
    function offerForSale(uint256 animalNumber, uint256 price) external onlyAnimalOwner(animalNumber) {
        if (price == 0) revert ZeroPrice();
        _salePrices[animalNumber] = price;
        emit AnimalOfferedForSale(animalNumber, price);
    }

    /// @notice Indique si un animal est en vente.
    function isAnimalForSale(uint256 animalNumber) external view returns (bool) {
        return _salePrices[animalNumber] != 0;
    }

    /// @notice Prix de vente d'un animal (0 s'il n'est pas en vente).
    function animalPrice(uint256 animalNumber) external view returns (uint256) {
        return _salePrices[animalNumber];
    }

    /// @notice Achète un animal en vente en payant exactement son prix.
    function buyAnimal(uint256 animalNumber) external payable {
        uint256 price = _salePrices[animalNumber];
        if (price == 0) revert AnimalNotForSale(animalNumber);
        if (msg.value != price) revert WrongPayment(msg.value, price);

        address seller = ownerOf(animalNumber);
        // Effets avant interactions : le transfert efface aussi l'annonce (voir _update).
        // _transfer et non _safeTransfer : l'Evaluator n'implémente pas onERC721Received.
        _transfer(seller, msg.sender, animalNumber);

        // Interaction en dernier : on paie le vendeur.
        _pay(seller, price);

        emit AnimalSold(animalNumber, seller, msg.sender, price);
    }

    /// @dev Point de passage de tout mint/transfert/burn : une annonce ne doit pas
    ///      survivre à un changement de propriétaire (sinon le nouveau propriétaire
    ///      pourrait se faire acheter son animal au prix fixé par l'ancien).
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        delete _salePrices[tokenId];
        return super._update(to, tokenId, auth);
    }
}
