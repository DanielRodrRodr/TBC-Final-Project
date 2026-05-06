Verificar interfaz (ERC165)
Controlar maxTokens [uint256 public tokensSold; y en mint; require(tokensSold + tokensToMint <= maxTokens, "Max tokens alcanzado"); 0tokensSold += tokensToMint;]
revisar lo de ownable y owner

En la memoria hay que dejar claro que el control el minter es el mismo que el QuadraticVoting

---------------------------------------------------------
Falta por hacer:

Comprobar que funciona bien
Mirar riesgos de reentrada y otros riesgos posibles
Eficiencia del código
Saber el por qué de TODO


















