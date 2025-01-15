use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
use crate::data_structures::{
    WalletData, DefiData, ExchangeData, CreditScore, 
    ScoreFactors, ScoringPermission
};
use crate::data_provider::{IDataProviderDispatcher, IDataProviderDispatcherTrait};
use crate::scoring_engine::{IScoringEngineDispatcher, IScoringEngineDispatcherTrait};

#[starknet::interface]
trait ICreditScoreMain<TContractState> {
    // User functions
    fn submit_data(
        ref self: TContractState,
        wallet_data: WalletData,
        defi_data: DefiData,
        exchange_data: ExchangeData
    ) -> bool;
    
    fn get_credit_score(self: @TContractState) -> CreditScore;
    fn grant_score_access(ref self: TContractState, to: ContractAddress, permission_type: u8);
    fn revoke_score_access(ref self: TContractState, from: ContractAddress);
    
    // Data provider functions
    fn register_data_provider(ref self: TContractState, provider: ContractAddress, name: felt252);
    fn remove_data_provider(ref self: TContractState, provider: ContractAddress);
    
    // Admin functions
    fn set_scoring_parameters(ref self: TContractState, new_weights: ScoreFactors);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

#[starknet::contract]
mod CreditScoreMain {
use starknet::storage::{StoragePointerWriteAccess, StorageMapWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, Map};

use super::*;
     // use super::Constants; // Commented out as Constants module is not defined
    mod Errors {
        pub const SYSTEM_PAUSED: felt252 = 1;
        pub const INVALID_STATE: felt252 = 2;
        pub const INVALID_PARAMETERS: felt252 = 3;
        pub const INSUFFICIENT_PERMISSION: felt252 = 4;
        pub const INVALID_TIMEFRAME: felt252 = 5;
    }
    
    #[storage]
    struct Storage {
        // Core components
        scoring_engine: ContractAddress,
        data_provider: ContractAddress,
        
        // User data and permissions
        user_scores: Map<ContractAddress, CreditScore>,
        score_permissions: Map<(ContractAddress, ContractAddress), ScoringPermission>,
        
        // Provider management
        data_providers: Map<ContractAddress, bool>,
        provider_names: Map<ContractAddress, felt252>,
        
        // Admin control
        admin: ContractAddress,
        paused: bool,
        
        // System parameters
        min_data_freshness: u64,  // Maximum age of data in seconds
        score_validity_period: u64 // How long a score remains valid
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DataSubmitted: DataSubmitted,
        ScoreUpdated: ScoreUpdated,
        AccessGranted: AccessGranted,
        AccessRevoked: AccessRevoked,
        ProviderRegistered: ProviderRegistered,
        ProviderRemoved: ProviderRemoved,
        SystemPaused: SystemPaused,
        SystemUnpaused: SystemUnpaused
    }

    // Event structs
    #[derive(Drop, starknet::Event)]
    struct DataSubmitted {
        user: ContractAddress,
        provider: ContractAddress,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ScoreUpdated {
        user: ContractAddress,
        new_score: u256,
        confidence: u8,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct AccessGranted {
        from: ContractAddress,
        to: ContractAddress,
        permission_type: u8,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct AccessRevoked {
        from: ContractAddress,
        to: ContractAddress,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ProviderRegistered {
        provider: ContractAddress,
        name: felt252,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ProviderRemoved {
        provider: ContractAddress,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct SystemPaused {
        by: ContractAddress,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct SystemUnpaused {
        by: ContractAddress,
        timestamp: u64
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin_address: ContractAddress,
        scoring_engine: ContractAddress,
        data_provider: ContractAddress
    ) {
        self.admin.write(admin_address);
        self.scoring_engine.write(scoring_engine);
        self.data_provider.write(data_provider);
        self.paused.write(false);
        
        // Set default parameters
        self.min_data_freshness.write(604800); // 1 week
        self.score_validity_period.write(2592000); // 30 days
    }

    #[abi(embed_v0)]
    impl CreditScoreMain of super::ICreditScoreMain<ContractState> {
        fn submit_data(
            ref self: ContractState,
            wallet_data: WalletData,
            defi_data: DefiData,
            exchange_data: ExchangeData
        ) -> bool {
            assert(!self.paused.read(), Errors::SYSTEM_PAUSED);
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            
            // Validate data through data provider
            let data_provider = self.data_provider.read();
            let data_provider_dispatcher = IDataProviderDispatcher { contract_address: data_provider };
            data_provider_dispatcher.submit_wallet_data(caller, wallet_data);
            data_provider_dispatcher.submit_defi_data(caller, defi_data);
            data_provider_dispatcher.submit_exchange_data(caller, exchange_data);
            
            // Calculate new score
            let scoring_engine = self.scoring_engine.read();
            let scoring_engine_dispatcher = IScoringEngineDispatcher { contract_address: scoring_engine };
            let new_score: CreditScore = scoring_engine_dispatcher.calculate_credit_score(
                wallet_data,
                defi_data,
                exchange_data
            );
            
            // Update storage
            self.user_scores.write(caller, new_score);
            
            self.emit(Event::DataSubmitted(
                DataSubmitted {
                    user: caller,
                    provider: get_caller_address(),
                    timestamp
                }
            ));
            
            self.emit(Event::ScoreUpdated(
                ScoreUpdated {
                    user: caller,
                    new_score: new_score.score,
                    confidence: new_score.confidence_level,
                    timestamp
                }
            ));
            
            true
        }

        fn get_credit_score(self: @ContractState) -> CreditScore {
            let _caller = get_caller_address();
            let score: CreditScore = self.user_scores.read(_caller);
            
            // Verify score is still valid
            let current_time = get_block_timestamp();
            assert(
                current_time - score.last_update <= self.score_validity_period.read(),
                Errors::INVALID_STATE
            );
            
            score
        }

        fn grant_score_access(
            ref self: ContractState,
            to: ContractAddress,
            permission_type: u8
        ) {
            assert(!self.paused.read(), Errors::SYSTEM_PAUSED);
            let caller = get_caller_address();
            
            // Validate permission type
            assert(permission_type <= 3, Errors::INVALID_PARAMETERS);
            
            let _permission = ScoringPermission {
                granted_by: caller,
                granted_to: to,
                permission_type: permission_type,
                expiry: get_block_timestamp() + 2592000,   // 30 days default
            };
            
            self.score_permissions.write((caller, to), _permission);

            
            self.emit(Event::AccessGranted(
                AccessGranted {
                    from: caller,
                    to,
                    permission_type,
                    timestamp: get_block_timestamp()
                }
            ));
        }

        fn revoke_score_access(ref self: ContractState, from: ContractAddress) {
            let caller = get_caller_address();
            let _permission = ScoringPermission {
                granted_to: from,
                granted_by: caller,
                permission_type: 0,
                expiry: 0
            };
            self.score_permissions.write((caller, from), _permission);
            
            self.emit(Event::AccessRevoked(
                AccessRevoked {
                    from: caller,
                    to: from,
                    timestamp: get_block_timestamp()
                }
            ));
        }

        fn register_data_provider(
            ref self: ContractState,
            provider: ContractAddress,
            name: felt252
        ) {
            self._only_admin();
            assert(!self.data_providers.read(provider), 'Provider already registered');
            
            self.data_providers.write(provider, true);
            self.provider_names.write(provider, name);
            
            self.emit(Event::ProviderRegistered(
                ProviderRegistered {
                    provider,
                    name,
                    timestamp: get_block_timestamp()
                }
            ));
        }

        fn remove_data_provider(ref self: ContractState, provider: ContractAddress) {
            self._only_admin();
            assert(self.data_providers.read(provider), 'Provider not registered');
            
            self.data_providers.write(provider, false);
            
            self.emit(Event::ProviderRemoved(
                ProviderRemoved {
                    provider,
                    timestamp: get_block_timestamp()
                }
            ));
        }

        fn set_scoring_parameters(ref self: ContractState, new_weights: ScoreFactors) {
            self._only_admin();
            let scoring_engine_address = self.scoring_engine.read();
            let scoring_engine_dispatcher = IScoringEngineDispatcher { contract_address: scoring_engine_address };
            scoring_engine_dispatcher.update_score_weights(new_weights);
        }

        fn pause(ref self: ContractState) {
            self._only_admin();
            assert(!self.paused.read(), 'Already paused');
            self.paused.write(true);
            
            self.emit(Event::SystemPaused(
                SystemPaused {
                    by: get_caller_address(),
                    timestamp: get_block_timestamp()
                }
            ));
        }

        fn unpause(ref self: ContractState) {
            self._only_admin();
            assert(self.paused.read(), 'Not paused');
            self.paused.write(false);
            
            self.emit(Event::SystemUnpaused(
                SystemUnpaused {
                    by: get_caller_address(),
                    timestamp: get_block_timestamp()
                }
            ));
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.admin.read() == caller, Errors::INSUFFICIENT_PERMISSION);
        }

        fn _validate_data_freshness(self: @ContractState, timestamp: u64) {
            let current_time = get_block_timestamp();
            assert(
                current_time - timestamp <= self.min_data_freshness.read(),
                Errors::INVALID_TIMEFRAME
            );
        }
    }
}