Verificar interfaz (ERC165)
Controlar maxTokens [uint256 public tokensSold; y en mint; require(tokensSold + tokensToMint <= maxTokens, "Max tokens alcanzado"); 0tokensSold += tokensToMint;]
revisar lo de ownable y owner
hay que mirar la implementación de Proposals, porque habría qe aberse los id de las cosas para poder ejecutarlos.
Hay que cambiar lo del VotingToken, ahora no se puede dar permiso al approve desde el contrato, la única opción es que el contarto sea independiente y tengamos la address.
En la memoria hay que dejar claro que el control el minter es el mismo que el QuadraticVoting
Mirar las funciones payable
Di pasas demiado eth en add participant da error, no se sabe por que 

---------------------------------------------------------
Falta por hacer:

Comprobar que funciona bien
Mirar riesgos de reentrada y otros riesgos posibles
Eficiencia del código
Saber el por qué de TODO


















