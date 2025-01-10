use starknet::{ContractAddress, get_caller_address, get_block_timestamp};


#[starknet::interface]
trait IZkVerifier<TContractState> {
    fn verify_proof(
        ref self: TContractState,
        proof_a: (felt252, felt252),
        proof_b: ((felt252, felt252), (felt252, felt252)),
        proof_c: (felt252, felt252),
        public_inputs: Span<felt252>
    ) -> bool;
    fn get_credit_score(self: @TContractState, user: ContractAddress) -> u256;
    fn update_verification_key(ref self: TContractState, new_key: (felt252, felt252));
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

#[starknet::contract]
mod ZkVerifier {
use starknet::storage::StorageMapReadAccess;
use starknet::storage::StorageMapWriteAccess;
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
use super::{ContractAddress, get_caller_address, get_block_timestamp};

    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    const MIN_SCORE: u256 = 300;
    const MAX_SCORE: u256 = 850;

    #[storage]
    struct Storage {
        credit_scores: Map<ContractAddress, u256>,
        last_update: Map<ContractAddress, u64>,
        admin: ContractAddress,
        verification_key: (felt252, felt252),
        roles: Map<felt252, ContractAddress>,
        paused: bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ProofVerified: ProofVerified,
        ScoreUpdated: ScoreUpdated,
        KeyUpdated: KeyUpdated,
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    struct ProofVerified {
        #[key]
        user: ContractAddress,
        is_valid: bool,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ScoreUpdated {
        #[key]
        user: ContractAddress,
        old_score: u256,
        new_score: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct KeyUpdated {
        old_key: (felt252, felt252),
        new_key: (felt252, felt252)
    }

    #[derive(Drop, starknet::Event)]
    struct Paused {
        by: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct Unpaused {
        by: ContractAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress, vk: (felt252, felt252)) {
        self.admin.write(admin_address);
        self.verification_key.write(vk);
        self.roles.write(ADMIN_ROLE, admin_address);
        self.paused.write(false);
    }

    #[abi(embed_v0)]
    impl ZkVerifier of super::IZkVerifier<ContractState> {
        fn verify_proof(
            ref self: ContractState,
            proof_a: (felt252, felt252),
            proof_b: ((felt252, felt252), (felt252, felt252)),
            proof_c: (felt252, felt252),
            public_inputs: Span<felt252>
        ) -> bool {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();

            let is_valid = self._verify_groth16(
                proof_a,
                proof_b,
                proof_c,
                public_inputs.clone()
            );

            if is_valid {
                let credit_score: u256 = (*public_inputs.at(0)).into();
                assert(credit_score >= MIN_SCORE && credit_score <= MAX_SCORE, 'Invalid score range');

                let old_score = self.credit_scores.read(caller);
                self.credit_scores.write(caller, credit_score);
                self.last_update.write(caller, timestamp);

                self.emit(Event::ProofVerified(ProofVerified {
                    user: caller,
                    is_valid: true,
                    timestamp: timestamp
                }));

                self.emit(Event::ScoreUpdated(ScoreUpdated {
                    user: caller,
                    old_score: old_score,
                    new_score: credit_score,
                    timestamp: timestamp
                }));
            }

            is_valid
        }

        fn get_credit_score(self: @ContractState, user: ContractAddress) -> u256 {
            self.credit_scores.read(user)
        }

        fn update_verification_key(ref self: ContractState, new_key: (felt252, felt252)) {
            self._only_admin();
            let old_key = self.verification_key.read();
            self.verification_key.write(new_key);
            self.emit(Event::KeyUpdated(KeyUpdated { old_key, new_key }));
        }

        fn pause(ref self: ContractState) {
            self._only_admin();
            assert(!self.paused.read(), 'Already paused');
            self.paused.write(true);
            self.emit(Event::Paused(Paused { by: get_caller_address() }));
        }

        fn unpause(ref self: ContractState) {
            self._only_admin();
            assert(self.paused.read(), 'Not paused');
            self.paused.write(false);
            self.emit(Event::Unpaused(Unpaused { by: get_caller_address() }));
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _verify_groth16(
            self: @ContractState,
            proof_a: (felt252, felt252),
            proof_b: ((felt252, felt252), (felt252, felt252)),
            proof_c: (felt252, felt252),
            public_inputs: Span<felt252>
        ) -> bool {
            // Basic verification logic - to be expanded
            let point_valid = self._verify_on_curve(proof_a);
            point_valid
        }

        fn _verify_on_curve(self: @ContractState, point: (felt252, felt252)) -> bool {
            // y^2 = x^3 + 3 (simplified BN254 curve equation)
            let (x, y) = point;
            let y2 = y * y;
            let x3 = x * x * x;
            y2 == (x3 + 3)
        }

        fn _only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.roles.read(ADMIN_ROLE) == caller, 'Caller is not admin');
        }
    }
}