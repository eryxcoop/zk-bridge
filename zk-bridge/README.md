# Documentation for ZK Bridge - Milestone 3

In this documentation we will describe the technical details of the validators needed to implement the locking transaction of our bridge. In order to do this, let's first describe our locking transaction.

## Locking transaction

The objective of this step is to lock a certain amount of assets in the unlocking validator. This is because the action of spending this UTxO will be in the context of unlocking funds in a full bridge.

In this version of the bridge, there's a single UTXO that amounts to the full locked value. This can easily be extended to multiple UTxOs by taking the total amount into account.

All the locked funds must be in a single output. Since we're using the tx ID to check if there's double spending, if two different UTxOs from the same tx contain locked funds, the second one will be impossible to mint. This output should be addressed to the `payment_address` of `Script(unlocking_validator)`. In the one-way version these funds will always stay locked. In a full bridge, this validator checks whether the withdrawal of these funds should be allowed, requiring a proof of burning wrapped assets in the destination chain.

The locked output's datum should also contain the `bridge_id` to allow only one bridge to use it for minting in the destination chain. Otherwise, a malicious user could use the same transaction to mint wrapped assets in multiple chains. It also should include the destination address of the minted funds in the destination chain (for example, in Cardano that would be the corresponding `payment_address`).

In summary, the tx has one or many inputs and one output that:
- contains he full amount locked funds in its `Value`.
- is addressed to the `payment_address` of `Script(unlocking_validator)`.
- has the `bridge_id` and the `destination_address` for the destination chain in its `Datum`.

## Unlocking transaction

As we said before, the output of the locking transaction will have the `Script(unlocking_validator)` as its address. This means that, in order to be able to create a locking transaction we need to write the unlocking validator and thus think about the unlocking transaction as well.

The unlocking transaction will need to do three things:
1. Create an output that contains the unlocked funds addressed to the `destination_address` specified in the locking transaction.
2. Verify a proof that there is a transaction named `burning_tx` in the destination chain that burns the corresponding wrapped assets. This proof will be a ZK proof.
3. Check that `burning_tx` was not used before to unlock funds in out chain. This is to prevent double unlocking.

We can summarize one part as "the correct assets are being unlocked" (points 1 and 2) and the other one as "the system will forbid this proof to be used to unlock funds again" (point 3).

Regarding point 2, the ZK proof will be a `Groth16` proof that proves the existence of a valid `burning_tx` that burns the correct amount of wrapped assets, addressed to the correct bridge's address. The characteristics of this proof will depend on the destination chain, but choosing a destination chain is not part of this project. Therefore, we will use an example circuit without any restrictions for the proof to act as a placeholder.

And regarding point 3, we will need to store the set of used transactions (or, as we will see, a commitment of that set) somewhere on-chain, so that we can check that `burning_tx` is not in that set. The next section will cover this topic in more detail.

We came to the conclusion that we need two Aiken validators, one that covers points 1 and 2 named `unlocking_validator`, and another one that covers point 3 named `txs_updater_validator`.

### Used transactions set (txs_updater_validator)

We need to store the transactions that have already been used to unlock funds somewhere on-chain, because otherwise there's no way to prevent double minting/unlocking by using the same proof twice.

To implement this, we have to store used transactions in a set that can answer efficiently that a certain tx ID does NOT belong to it, because if this condition is true, then the validator can allow the action. In particular, we enable the creation of proofs of absence from the set. For this, we can store it in a sparse Merkle Tree (MT).

We commit to the root of the tree in a UTxO's datum, that will be identified with a particular NFT for this purpose. The action of unlocking should ensure that the provided transaction hasn't been used before (by verifying a proof of absence) and also transform the used transactions set (i.e. spend the corresponding UTxO and replace it with another one) so that it contains exactly all the transactions it contained before, plus the new one. It should also check that the new transactions set UTxO is well formed: it should contain the identifier NFT and preserve the same rules for spending it to further update the set.

More specifically, a valid transaction set UTxO contains a `merkle_root` field in its `Datum` that corresponds to a sparse MT of transaction ids. The preservation of rules is guaranteed by always sending the UTxOs to the address of the `txs_updater_validator.spend` validator.

The action of spending a used transactions set includes `H(tx)` (the hash of the corresponding locking/burning transaction) in the corresponding `Redeemer`. We can't pass the whole transaction in the redeemer because `Transaction` is an _opaque type_ (because it contains a `Value` that is a dictionary-like type). See the "Opaque types" section below for more details.

Also, note that the actual elements of the set are never stored on-chain because there's no reasonable upper bound for the size of that structure, so it's assumed that the set is published somewhere off-chain in order to enable people to build the proofs. In all the generated proofs, the list of elements will be a private input of the prover.

The validator to spend (update) the used transaction set from an `old_merkle_root` status to a `new_merkle_root` one checks that:
- A valid ZK proof that:
    - `H(tx)` doesn't belong to the set represented by `old_merkle_root` is provided.
    - The `new_merkle_root` is the result of correctly updating the tx set represented by `old_merkle_root`. This means that a private set of transaction IDs `S` exists such that `old_merkle_root` represents `S` and `new_merkle_root` represents `S U H(tx)`.
- The new used transaction set UtxO contains the same NFT than the old one.
- The new used transaction set UtxO is also sent to the same address, so it has the same validator than the old one (`txs_updater_validator.spend`).

The code of this validator can be found at `validators/txs_updater.ak`. Regarding the ZK proof, we used a placeholder circuit that can be found at `circuits/txs_updater_circuit.circom`. In the next milestone we will provide the circuit that actually implements the logic described above.

It's assumed that there's a bootstrapping process that includes the minting of the NFT, along with the representation of an empty set of used transactions, this is explained in the `txs_updater_validator.mint` validator.

### Unlocking validator

To unlock the assets in our chain we must provide a proof of having burned the corresponding wrapped assets in the destination chain, along with all the necessary information to verify said proof on-chain.

This means the `Redeemer` must contain:
- a `Groth16` `BurningProof`
- the `destination_address` for the unlocked funds in our chain.
- information about the burned funds in the destination chain: amount and token name. Since we're working with Cardano, "token name" would be the pair (`policy_id`, `token_name`).

We didn't make a real burning proof because, as said in a previous section, the burning proof depends on the destination chain an that's beyond the scope of this project. Instead, a place-holder proof was introduced in the code. The used circuit can be found at `circuits/burning_circuit.circom`.

The following validations should take place:
- There are an input and an output that represent a valid state transition for the used transactions set variable (as stated in the previous section, and that add the correct transaction id hash to the set).
- The ZK proof is valid with the provided inputs.
- There's another output that represents the unlocked funds and
    - its amount corresponds to that of the burned assets
    - its destination address corresponds to the authorized recipient
- If there's an additional change output, it's addressed back to the address of the script. More than one change outputs shouldn't be allowed.

### Guaranteeing atomicity

There are instances in which we need to mantain atomicity between two actions. This means that both actions shoud succeed or fail together as an undivisible unit. In our case, both the minting and the unlocking actions need to happen if and only if the corresponding used transactions set is updated.

To achieve this, it suffices for each of the scripts to require that the other part of the process is present in the same transaction in which the script is executed. This translated to the following statements, that imply the condition both ways:
- The used transaction set validator requires that another UTxO of the transaction has `unlocking_validator.spend` (or the corresponding one for minting) as a validator. This implies that every time that a transaction id is added to the used set, then a minting/unlocking of funds was performed.
- The minting/unlocking validator must check that there's another input that contains the NFT that corresponds to the used transactions set, so that every time a minting/unlocking occurs, the action fo adding the corresponding transaction id to the used set happens too.

Note that this doesn't mean we're running any additional validator manually, only that we're checking that the validator's hash is the UTxO's address. This is because, if that UTxO is spent, then it means that the corresponding validator has passed.

Note that this process requires that the files are compiled in a certain order:
- First, the `txs_updater_validator_mint.mint` validator, to obtain the NFT's `PolicyId`.
- Second, the `unlocking_validator.spend` validator, to obtain its address.
- Third, the `txs_updater_validator_spend.spend` validator.

After each compilation, the corresponding hash should be copied and pasted in the corresponding variable in the env file.

## Technical considerations

Here are some general considerations that apply to more than one validator, so that they can be referenced in many places in the following text. Keep them in mind while browsing the whole codebase.

### Opaque types

An _opaque type_ is one that has some restrictions that cannot be enforced by shape alone: there are some structures that "look like" the type but aren't valid instances, because they have a non-trivial _type invariant_. For example, a dictionary shouldn't have repeated keys, but you can write a representation (think a JSON-like structure) that looks like a dictionary but when you interpret it, it has a repeated key with different values, so it doesn't comply with the invariant.

In Cardano, this makes `Value` an _opaque type_ because it's a kind of dictionary. Everything that contains an opaque type is also opaque, so `Transaction` is too. Aside from the technical restrictions, it's reasonable to treat `Transaction` as an abstract type, too, because in the general case we may be receiving proofs for chains other than Cardano, which will have a different way of representing them. This way, the only assumption that we can (and should) make about a transaction in any chain is that it has an identifier that can be hashed in a certain way. This means that we will be identifying transactions by hashing their identifiers, whatever that means in each blockchain.

## MIN_ADA requirement

Each UTxO is required to contain a MIN_ADA amount in its `Value`, independently of other tokens it might contain. This means that, under some conditions, an additional ADA amount should be provided for a transaccion to succeed. For example, if one wants to unlock some assets that are a part of a bigger UTxO, maybe this UTxO will split in two (one to the recipient for the unlocked amount, and another one to the script address with the change). If the input transaction has less than twice MIN_ADA, the bridge user must supply up to MIN_ADA to allow both outputs to exist.

If the bridge always keeps a sufficient amount of ADA in a pool to subsidize the creation of new UTxOs this is not a problem, but there are scenarios in which the bridge might fail to create unlocking UTxOs, or that it will, in reality, have less ADA than the full locked amount.

There might be different ways to tackle this issue in a bridge that's meant for production: for example, an administrator action that injects ADA to the bridge every now and then, or always asking for the final user to provide this amount of ADA from an alternate source. Our intuition is that it's fairer to ask for the final user to provide MIN_ADA that are then returned to them in the output UTxO. This has the downside that some ADA might accumulate over time in the bridge address because of the locking transactions that lock assets other than ADA, and that remainder might be irrecoverable.

We're not solving this problem in the scope of this project.

## Testing

There are Aiken tests for the unlocking script and the used transactions set in [this file](validators/tests/unlocking_test.ak) and [this file](validators/tests/txs_updater_test.ak) respectively. Their names are mostly self-explanatory.

To run the tests, just [install Aiken](https://aiken-lang.org/installation-instructions) and use the command:

```bash
cd zk-bridge
aiken check
```

