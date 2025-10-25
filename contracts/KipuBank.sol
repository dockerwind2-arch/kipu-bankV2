// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @dev Interfaz token ERC20
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}


/// @title KipuBank
/// @notice Contrato que permite a los usuarios depositar y retirar ETH con límites definidos.
/// @dev Sigue buenas prácticas de seguridad y patrones de Solidity.

contract KipuBank is ReentrancyGuard, AccessControl  {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Límite fijo de retiro por transacción (en wei).
    /// @dev Se establece en el constructor y no puede modificarse.
    uint256 public immutable withdrawLimit;

    /// @notice Capital global de depósitos que puede recibir el banco.
    /// @dev Se establece en el constructor y no puede modificarse.
    uint256 public immutable bankCap;

    /// @notice Capital global del banco en USD (8 decimales)
    uint256 public bankCapUSD;

    /// @notice Registro del total depositado en el banco.
    uint256 public totalDeposited;

    /// @notice Registro del número de depósitos realizados.
    uint256 public totalDeposits;

    /// @notice Registro del número de retiros realizados.
    uint256 public totalWithdrawals;

    /// @notice genera un identificador único para el rol.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Oráculo de Chainlink para precio ETH/USD
    AggregatorV3Interface public priceFeed;

    /// @notice Bóvedas personales de cada usuario por token.
    /// @dev address(0) representa ETH nativo.
    mapping(address => mapping(address => uint256)) private vaults;

    /// @notice Mapea un token a su Chainlink Data Feed (USD)
    mapping(address => AggregatorV3Interface) public tokenPriceFeeds;

    /*//////////////////////////////////////////////////////////////
                                EVENTOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitido cuando un usuario deposita ETH exitosamente.
    /// @param user Dirección del usuario que deposita.
    /// @param amount Monto depositado en wei.
    event Deposited(address indexed user, uint256 amount);

    /// @notice Emitido cuando un usuario retira ETH exitosamente.
    /// @param user Dirección del usuario que retira.
    /// @param amount Monto retirado en wei.
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitido cuando se cambia el administrador del contrato.
    /// @param oldAdmin Dirección del administrador anterior.
    /// @param newAdmin Dirección del nuevo administrador.
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Emitido cuando se asigna un Chainlink feed a un token ERC20.
    /// @param token Dirección del token al que se le asigna el feed.
    /// @param feed Dirección del Chainlink feed asignado.
    event TokenFeedSet(address indexed token, address indexed feed);

    /*//////////////////////////////////////////////////////////////
                                 ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Error cuando la llamada no proviene del owner.
    error ErrorNotOwner();

    /// @notice Error cuando el depósito excede el límite global del banco.
    error ErrorDepositoExcedeCap();

    /// @notice Error cuando el retiro excede el límite permitido por transacción.
    error ErrorRetiroExcedeLimite();

    /// @notice Error cuando el usuario no tiene fondos suficientes en su bóveda.
    error ErrorFondosInsuficientes();
    
    /// @notice Error cuando la transferencia de ETH falla.
    error ErrorTransferenciaFallida();

    /// @notice Error cuando amount es inválido.
	error ErrorMontoInvalido();

    /// @notice Error cuando depósito es inválido.
    error DepositoInvalido();

    /// @notice Error feed no disponible.
    error FeedNoDisponible();


    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _withdrawLimit Límite máximo de retiro por transacción.
    /// @param _bankCap Capital global de depósitos para el banco.
    /// @param _bankCapUSD Capital global de depósitos en dolares para el banco.
    /// @param _priceFeed dirección del oráculo ETH/USD.
    constructor(uint256 _withdrawLimit, uint256 _bankCap, uint256 _bankCapUSD, address _priceFeed) {
        withdrawLimit = _withdrawLimit;
        bankCap = _bankCap;
        bankCapUSD = _bankCapUSD;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
         priceFeed = AggregatorV3Interface(_priceFeed);
    }

 /*//////////////////////////////////////////////////////////////
                               MODIFIER
    //////////////////////////////////////////////////////////////*/

    /// @notice Modificador para validar montos mayores a cero.
    /// @param amount Monto que se desea usar en una transacción.
    modifier validAmount(uint256 amount) {
       if (amount == 0) revert ErrorMontoInvalido();
       _;
    }

    /// @notice Modificador que restringe la ejecución al owner.
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert ErrorNotOwner();
    _   ;
    }
    
    /*//////////////////////////////////////////////////////////////
                                FUNCIONES
    //////////////////////////////////////////////////////////////*/

    /// @notice Permite a un usuario depositar ETH en su bóveda.
    /// @dev Revierte si el depósito supera el límite global.
      function deposit() external payable nonReentrant{
        if (msg.value == 0) revert DepositoInvalido();

        uint256 depositUSD = _ethToUSD(msg.value);
        uint256 totalDepositedUSD = _ethToUSD(totalDeposited);

        if (totalDepositedUSD + depositUSD > bankCapUSD) {
            revert ErrorDepositoExcedeCap();
        }
        
        if (totalDeposited + msg.value > bankCap) {
            revert ErrorDepositoExcedeCap();
        }

        vaults[msg.sender][address(0)] += msg.value;
        totalDeposited += msg.value;
        totalDeposits++;

       emit Deposited(msg.sender, msg.value);
    }

    /// @notice Permite depositar ETH o tokens ERC20.
    /// @param token Dirección del token (usar address(0) para ETH).
    /// @param amount Monto a depositar (ignorado si es ETH).
    function depositToken(address token, uint256 amount) external payable nonReentrant validAmount(msg.value > 0 ? msg.value : amount) {
        uint256 depositAmount;
        
        if (token == address(0)) {
            // Deposito de ETH
            if (msg.value == 0) revert DepositoInvalido();
            depositAmount = msg.value;
            if (totalDeposited + depositAmount > bankCap) revert ErrorDepositoExcedeCap();
        } else {
            // Deposito de token ERC20
            depositAmount = amount;
            if (!IERC20(token).transferFrom(msg.sender, address(this), depositAmount)) {
                revert ErrorTransferenciaFallida();
            }
        }

        uint256 depositUSD = _tokenToUSD(token, depositAmount);
        uint256 totalDepositedUSD = _tokenToUSD(address(0), totalDeposited);
        if (totalDepositedUSD + depositUSD > bankCapUSD) {
            revert ErrorDepositoExcedeCap();
        }

        vaults[msg.sender][token] += depositAmount;
        totalDeposited += depositAmount;
        totalDeposits++;

        emit Deposited(msg.sender, depositAmount);
    }


    /// @notice Permite a un usuario retirar fondos de su bóveda, respetando el límite por transacción.
    /// @dev Revierte si el retiro excede el limite y si los fondos son insuficientes.
    /// @param amount Monto a retirar en wei.
    function withdraw(uint256 amount) external validAmount(amount) nonReentrant{
        if (amount > withdrawLimit) {
            revert ErrorRetiroExcedeLimite();
        }
        if (vaults[msg.sender][address(0)] < amount){
            revert ErrorFondosInsuficientes();
        }

        vaults[msg.sender][address(0)] -= amount;
        totalDeposited -= amount;
        totalWithdrawals++;
    
        _safeTransfer(address(0), msg.sender, amount);
         emit Withdrawn(msg.sender, amount);
    }

    /// @notice Permite retirar ETH o tokens ERC20 de la bóveda.
    /// @param token Dirección del token (usar address(0) para ETH).
    /// @param amount Monto a retirar.
    function withdrawToken(address token, uint256 amount) external validAmount(amount) nonReentrant{
        if (amount > withdrawLimit) revert ErrorRetiroExcedeLimite();
        if (vaults[msg.sender][token] < amount) revert ErrorFondosInsuficientes();

        vaults[msg.sender][token] -= amount;
        totalDeposited -= amount;
        totalWithdrawals++;

        _safeTransfer(token, msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }


    /// @notice Realiza una transferencia segura de ETH o ERC20.
    /// @param token Dirección del token (usar address(0) para ETH).
    /// @param to Destinatario.
    /// @param amount Monto a transferir.
    function _safeTransfer(address token, address to, uint256 amount) private {
        bool success;

        if (token == address(0)) {
            // Transferencia nativa (ETH)
            (success, ) = to.call{value: amount}("");
        } else {
            // Transferencia ERC20
            success = IERC20(token).transfer(to, amount);
        }

        if (!success) revert ErrorTransferenciaFallida();
    }

    
    
    /// @notice Devuelve el balance de un usuario para un token específico.
    /// @param user Dirección del usuario.
    /// @param token Dirección del token (usar address(0) para ETH).
    /// @return Balance en unidades del token.
    function getVaultBalance(address user, address token) external view returns (uint256) {
        return vaults[user][token];
    }
    
    /// @notice Devuelve el precio ETH/USD con 8 decimales.
    /// @return price Precio actual de ETH en USD.
    function getLatestETHPrice() public view returns (int256 price) {
        (, price, , ,) = priceFeed.latestRoundData();
    }

    /// @notice Convierte ETH (wei) a USD usando Chainlink.
    /// @param amountETH Monto en wei.
    /// @return amountUSD Monto equivalente en USD (8 decimales).
    function _ethToUSD(uint256 amountETH) internal view returns (uint256 amountUSD) {
        int256 price = getLatestETHPrice();
        if (price <= 0) revert DepositoInvalido();
        amountUSD = (amountETH * uint256(price)) / 1e18;
    }

    /// @notice Convierte un monto de token a USD usando su feed.
    /// @param token Dirección del token (usar address(0) para ETH)
    /// @param amount Monto en unidades del token
    /// @return amountUSD Monto equivalente en USD (8 decimales)
    function _tokenToUSD(address token, uint256 amount) internal view returns (uint256 amountUSD) {
        AggregatorV3Interface feed = token == address(0) ? priceFeed : tokenPriceFeeds[token];
        if (address(feed) == address(0)) revert FeedNoDisponible();

        (, int256 price,,,) = feed.latestRoundData();
        if (price <= 0) revert DepositoInvalido();

        uint8 tokenDecimals = token == address(0) ? 18 : IERC20(token).decimals();
        amountUSD = (amount * uint256(price)) / (10 ** tokenDecimals);
    }


    /// @notice  Maneja depósitos directos de ETH enviados sin usar la función deposit().
    receive() external payable {
         if (msg.value == 0) revert DepositoInvalido();
        uint256 depositUSD = _ethToUSD(msg.value);
        uint256 totalDepositedUSD = _ethToUSD(totalDeposited);
        if (totalDeposited + msg.value > bankCap || totalDepositedUSD + depositUSD > bankCapUSD) revert ErrorDepositoExcedeCap();
        vaults[msg.sender][address(0)] += msg.value;
        totalDeposited += msg.value;
        totalDeposits++;
        emit Deposited(msg.sender, msg.value);
    }
    
    /// @notice Maneja llamadas inválidas o funciones inexistentes, permitiendo depósito de ETH.
    fallback() external payable {
        if (msg.value == 0) revert DepositoInvalido();
        uint256 depositUSD = _ethToUSD(msg.value);
        uint256 totalDepositedUSD = _ethToUSD(totalDeposited);
        if (totalDeposited + msg.value > bankCap || totalDepositedUSD + depositUSD > bankCapUSD) revert ErrorDepositoExcedeCap();
        vaults[msg.sender][address(0)] += msg.value;
        totalDeposited += msg.value;
        totalDeposits++;
        emit Deposited(msg.sender, msg.value);
    }


    /*//////////////////////////////////////////////////////////////
                              UTILS/ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfiere la propiedad del contrato a otra cuenta.
    /// @param newAdmin Dirección del nuevo owner.
    function transferOwnership(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ErrorNotOwner();
         address oldAdmin = msg.sender;
         grantRole(ADMIN_ROLE, newAdmin);
         revokeRole(ADMIN_ROLE, msg.sender);
         emit AdminChanged(oldAdmin, newAdmin);
    }

    /// @notice Asigna un feed de Chainlink para un token ERC20
    /// @param token Dirección del token
    /// @param feed Dirección del Chainlink feed
    function setTokenPriceFeed(address token, address feed) external onlyAdmin {
        if (feed == address(0)) revert FeedNoDisponible();
        tokenPriceFeeds[token] = AggregatorV3Interface(feed);
        emit TokenFeedSet(token, feed);
    }
 }
