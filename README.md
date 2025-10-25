# KipuBankV2

Contrato inteligente en Solidity que permite a los usuarios depositar y retirar **ETH** y **tokens ERC20** con límites definidos, utilizando un oráculo de Chainlink y control de acceso avanzado.

---

## 📖 Descripción general

KipuBankV2 mejora el contrato anterior con:

- **Control de Acceso:** Uso de `AccessControl` de OpenZeppelin con un rol `ADMIN_ROLE` para operaciones administrativas como cambiar la propiedad o asignar feeds.
- **Declaraciones de Tipos y Errores Personalizados:** Se reemplazan strings por `error` para mayor eficiencia.
- **Instancia del Oráculo Chainlink:** Para obtener precios en USD de ETH y tokens ERC20 con feed configurables.
- **Variables Inmutables:** `withdrawLimit` y `bankCap` definidos en el constructor para mayor seguridad.
- **Mappings anidados:** Cada usuario tiene un mapping de balances por token (`vaults[user][token]`).
- **Funciones de conversión de decimales y valores:** `_ethToUSD` y `_tokenToUSD` para convertir montos a USD según el feed correspondiente.

---

## 📁 Estructura del repositorio

KipuBankV2/
├─ src/
│ └─ KipuBank.sol
├─ README.md
└─ .gitignore

markdown
Copy code

---

## ⚙️ Cómo desplegar

1. Abrir **Remix**.
2. Cargar `KipuBank.sol` en el editor.
3. Compilar con versión `>=0.8.2 <0.9.0`.
4. Conectar **MetaMask** a la testnet elegida (ej. Sepolia).
5. En Deploy, pasar los parámetros del constructor:

| Parámetro        | Ejemplo                        | Descripción                                  |
|-----------------|--------------------------------|----------------------------------------------|
| `_withdrawLimit` | 0.1 ETH → `100000000000000000` | Límite máximo de retiro por transacción     |
| `_bankCap`       | 10 ETH → `10000000000000000000` | Capital máximo del banco                     |
| `_bankCapUSD`    | 20,000 USD → `2000000000`       | Capital máximo del banco en USD (8 decimales) |
| `_priceFeed`     | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | ETH/USD Sepolia feed                        |

6. Hacer deploy y copiar la dirección del contrato.
7. Verificar el contrato en **Etherscan** (opcional).

---

## 📡 Interacciones principales

| Función | Descripción |
|---------|-------------|
| `deposit()` | Deposita ETH al contrato (revierte si excede el cap global). |
| `depositToken(address token, uint256 amount)` | Deposita tokens ERC20 o ETH (si `token = 0x0`). |
| `withdraw(uint256 amount)` | Retira ETH hasta `withdrawLimit`. |
| `withdrawToken(address token, uint256 amount)` | Retira tokens ERC20 hasta `withdrawLimit`. |
| `getVaultBalance(address user, address token)` | Consulta balance de un usuario por token. |
| `setTokenPriceFeed(address token, address feed)` | **Admin:** asigna el feed Chainlink de un token. |
| `transferOwnership(address newAdmin)` | **Admin:** transfiere rol de administrador. |

---

## 🔒 Seguridad y mejoras

- Uso de errores personalizados en lugar de strings para revertir.
- Aplicación del patrón **checks-effects-interactions** para evitar reentradas.
- Función `_safeTransfer` para manejo seguro de ETH y tokens.
- Variables `withdrawLimit` y `bankCap` inmutables para mayor confiabilidad.
- Integración con Chainlink para precios precisos y feeds configurables.
- Uso de `AccessControl` para separar funciones administrativas de las del usuario.

---

## 💡 Decisiones de diseño y trade-offs

- **Inmutables vs setters:** Se eligió inmutables para evitar cambios inesperados de límites críticos.
- **Mapping anidado:** Permite múltiples tokens por usuario, aumentando flexibilidad pero requiere cuidado en gas para iteraciones.
- **Chainlink feeds:** Se verifica disponibilidad, pero si un feed falla, la transacción revierte.
- **ERC20 generalizado:** No se limita a un token, lo que requiere validar correctamente transferencias y decimales.

---

## 📍 Dirección del contrato desplegado

- **Testnet:** Sepolia  
- **Dirección:** `0x515ee96f3bae4f4d6f8678bf493996c0defd91b4`  
- **Código verificado en:** [Etherscan Sepolia](https://sepolia.etherscan.io/address/0x515ee96f3bae4f4d6f8678bf493996c0defd91b4#code)
