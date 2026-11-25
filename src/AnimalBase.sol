// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AnimalBase - socle commun des contrats du TD "ERC721 101"
/// @notice Chaque token est un animal. Seuls les éleveurs (breeders) inscrits peuvent en créer,
///         et seul le propriétaire d'un animal peut le déclarer mort.
/// @dev Contrat abstrait : il n'est jamais déployé seul. Il est hérité par
///      - ExerciseSolution  (+ vente, ex6)          -> soumis à Evaluator
///      - ExerciseSolution2 (+ parents/reproduction) -> soumis à Evaluator2
///      Séparer les fonctionnalités garde chaque contrat sous la limite de gas de déploiement.
abstract contract AnimalBase is ERC721Enumerable, Ownable {
    // ───────────────────────────── Types & stockage ─────────────────────────────

    /// @dev Les caractéristiques que les Evaluators comparent avec celles attribuées par ex2a
    struct Animal {
        string name;
        bool wings;
        uint256 legs;
        uint256 sex;
    }

    /// @dev tokenId => caractéristiques de l'animal
    mapping(uint256 => Animal) private _animals;

    /// @dev Prochain id libre. Le token 1 est minté dans le constructeur, on commence à 2.
    uint256 private _nextId = 2;

    /// @notice Liste des éleveurs autorisés à déclarer des animaux
    mapping(address => bool) public isBreeder;

    /// @notice Prix (en wei) à payer pour devenir éleveur
    uint256 public registrationPrice = 0.0001 ether;

    // ───────────────────────────── Événements & erreurs ─────────────────────────

    event BreederRegistered(address indexed breeder);
    event RegistrationPriceUpdated(uint256 newPrice);
    event AnimalDied(uint256 indexed animalNumber, address indexed owner);

    error NotABreeder(address account);
    error AlreadyBreeder(address account);
    error WrongRegistrationPayment(uint256 sent, uint256 expected);
    error WithdrawFailed();
    error NotAnimalOwner(uint256 animalNumber, address caller);
    error ZeroPrice();
    error WrongPayment(uint256 sent, uint256 expected);
    error PaymentFailed();

    // ───────────────────────────── Modifiers ────────────────────────────────────

    modifier onlyBreeder() {
        if (!isBreeder[msg.sender]) revert NotABreeder(msg.sender);
        _;
    }

    /// @dev Factorise la vérification "l'appelant possède cet animal" (revert aussi si l'animal n'existe pas)
    modifier onlyAnimalOwner(uint256 animalNumber) {
        if (ownerOf(animalNumber) != msg.sender) revert NotAnimalOwner(animalNumber, msg.sender);
        _;
    }

    // ───────────────────────────── Constructeur ─────────────────────────────────

    /// @param evaluator Adresse de l'Evaluator qui recevra le token #1
    constructor(address evaluator) ERC721("TD Animals", "ANML") Ownable(msg.sender) {
        // Le déployeur est éleveur d'office, pour pouvoir déclarer ses propres animaux.
        isBreeder[msg.sender] = true;
        emit BreederRegistered(msg.sender);

        // _mint et non _safeMint : les Evaluators n'implémentent pas onERC721Received,
        // donc _safeMint revert en voyant un contrat incapable de "recevoir" un NFT.
        _mint(evaluator, 1);
    }

    // ───────────────────────────── Éleveurs (ex3) ───────────────────────────────

    /// @notice S'inscrire comme éleveur en payant exactement `registrationPrice`.
    function registerMeAsBreeder() external payable {
        if (isBreeder[msg.sender]) revert AlreadyBreeder(msg.sender);
        if (msg.value != registrationPrice) revert WrongRegistrationPayment(msg.value, registrationPrice);

        isBreeder[msg.sender] = true;
        emit BreederRegistered(msg.sender);
    }

    /// @notice Le propriétaire du contrat inscrit gratuitement un éleveur
    ///         (utile pour Evaluator2, qui ne s'inscrit jamais lui-même).
    function addBreeder(address account) external onlyOwner {
        if (isBreeder[account]) revert AlreadyBreeder(account);
        isBreeder[account] = true;
        emit BreederRegistered(account);
    }

    /// @notice Le propriétaire du contrat peut ajuster le prix d'inscription.
    function setRegistrationPrice(uint256 newPrice) external onlyOwner {
        registrationPrice = newPrice;
        emit RegistrationPriceUpdated(newPrice);
    }

    /// @notice Récupère les ETH payés par les éleveurs (sinon ils resteraient bloqués dans le contrat).
    function withdraw() external onlyOwner {
        (bool ok,) = payable(owner()).call{value: address(this).balance}("");
        if (!ok) revert WithdrawFailed();
    }

    // ───────────────────────────── Animaux (ex2, ex4) ───────────────────────────

    /// @notice Crée un nouvel animal et le donne à l'appelant. Réservé aux éleveurs.
    /// @return id L'identifiant du token créé
    function declareAnimal(uint256 sex, uint256 legs, bool wings, string calldata name)
        external
        onlyBreeder
        returns (uint256 id)
    {
        return _createAnimal(msg.sender, sex, legs, wings, name);
    }

    /// @notice Renvoie les caractéristiques d'un animal.
    /// @dev Ne revert PAS pour un animal inexistant/mort : ex5 attend ("", false, 0, 0)
    ///      après un burn, c'est-à-dire les valeurs par défaut d'une struct supprimée.
    function getAnimalCharacteristics(uint256 animalNumber)
        external
        view
        returns (string memory _name, bool _wings, uint256 _legs, uint256 _sex)
    {
        Animal storage a = _animals[animalNumber];
        return (a.name, a.wings, a.legs, a.sex);
    }

    // ───────────────────────────── Mort d'un animal (ex5) ───────────────────────

    /// @notice Déclare un animal mort : le token est brûlé et ses caractéristiques effacées.
    function declareDeadAnimal(uint256 animalNumber) external onlyAnimalOwner(animalNumber) {
        delete _animals[animalNumber]; // remet name/wings/legs/sex à leurs valeurs par défaut
        _burn(animalNumber);
        emit AnimalDied(animalNumber, msg.sender);
    }

    // ───────────────────────────── Helpers internes ─────────────────────────────

    /// @dev Point d'entrée unique de création d'animal, réutilisé par les contrats enfants.
    function _createAnimal(address to, uint256 sex, uint256 legs, bool wings, string calldata name)
        internal
        returns (uint256 id)
    {
        id = _nextId++;
        _animals[id] = Animal(name, wings, legs, sex);
        _mint(to, id);
    }

    /// @dev Envoie des ETH et revert si le destinataire les refuse.
    function _pay(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert PaymentFailed();
    }
}
