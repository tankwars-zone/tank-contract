const Web3 = require('Web3');

const web3 = new Web3();

const data = web3.eth.abi.encodeFunctionCall({
    name: 'initialize',
    type: 'function',
    inputs: []
}, []);

console.log('\n', data);