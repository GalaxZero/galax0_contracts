use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
use starknet::storage::{StoragePointerWriteAccess, Map};
use core::hash::LegacyHash;

use crate::data_structures::{WalletData, DefiData, ExchangeData, VerificationData};

#[starknet::interface]
pub trait IDataProvider<TContractState> {
    fn submit_wallet_data(ref self: TContractState, user: ContractAddress, data: WalletData) -> bool;
    fn submit_defi_data(ref self: TContractState, user: ContractAddress, data: DefiData) -> bool;
    fn submit_exchange_data(ref self: TContractState, user: ContractAddress, data: ExchangeData) -> bool;
    fn verify_data_submission(self: @TContractState, user: ContractAddress) -> VerificationData;
    fn get_verification_status(self: @TContractState, user: ContractAddress) -> u8;
}   

#[starknet::contract]
pub mod DataProvider {
use starknet::storage::StoragePointerReadAccess;
use starknet::storage::StorageMapReadAccess;
use starknet::storage::StorageMapWriteAccess;
use super::*;
    mod Errors {
        pub const INSUFFICIENT_PERMISSION: felt252 = 1;
        pub const RATE_LIMIT_EXCEEDED: felt252 = 2;
        pub const INVALID_PARAMETERS: felt252 = 3;
    }
    use starknet::get_contract_address;
    #[storage]
    struct Storage {
        // Registered data providers
        authorized_providers: Map<ContractAddress, bool>,
        provider_names: Map<ContractAddress, felt252>,
        
        // User data verification
        wallet_data_verified: Map<ContractAddress, bool>,
        defi_data_verified: Map<ContractAddress, bool>,
        exchange_data_verified: Map<ContractAddress, bool>,
        
        // Data submission timestamps
        last_wallet_update: Map<ContractAddress, u64>,
        last_defi_update: Map<ContractAddress, u64>,
        last_exchange_update: Map<ContractAddress, u64>,
        
        // Admin control
        admin: ContractAddress,
        paused: bool,
        
        // Rate limiting
        submission_count: Map<(ContractAddress, u64), u32>, // (provider, day) => count
        max_daily_submissions: u32
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DataSubmitted: DataSubmitted,
        ProviderAuthorized: ProviderAuthorized,
        ProviderRevoked: ProviderRevoked,
        DataVerified: DataVerified
    }

    #[derive(Drop, starknet::Event)]
    struct DataSubmitted {
        provider: ContractAddress,
        user: ContractAddress,
        data_type: felt252,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ProviderAuthorized {
        provider: ContractAddress,
        name: felt252,
        authorized_by: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ProviderRevoked {
        provider: ContractAddress,
        revoked_by: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct DataVerified {
        user: ContractAddress,
        data_type: felt252,
        verified_by: ContractAddress,
        timestamp: u64
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress) {
        self.admin.write(admin_address.into());
        self.paused.write(false.into());
        self.max_daily_submissions.write(1000); // Default rate limit
    }

    #[abi(embed_v0)]
    impl DataProvider of super::IDataProvider<ContractState> {
        fn submit_wallet_data(
            ref self: ContractState, 
            user: ContractAddress,
            data: WalletData
        ) -> bool {
            self._check_provider_authorization();
            self._enforce_rate_limit();
            
            let provider = get_caller_address();
            let timestamp = get_block_timestamp();
            
            // Validate data
            self._validate_wallet_data(@data);
            
            // Update storage
            self.wallet_data_verified.write(user.into(), true.into());
            self.last_wallet_update.write(user.into(), timestamp.into());
            
            // Update rate limiting
            let day = timestamp / 86400;
            let current_count = self.submission_count.read((provider.into(), day.into()));
            self.submission_count.write((provider.into(), day.into()), current_count + 1);
            
            // Emit event
            self.emit(Event::DataSubmitted(
                DataSubmitted {
                    provider,
                    user,
                    data_type: 'WALLET_DATA',
                    timestamp
                }
            ));
            
            true
        }

        fn submit_defi_data(
            ref self: ContractState,
            user: ContractAddress,
            data: DefiData
        ) -> bool {
            self._check_provider_authorization();
            self._enforce_rate_limit();
            
            let provider = get_caller_address();
            let timestamp = get_block_timestamp();
            
            // Validate data
            self._validate_defi_data(@data);
            
            // Update storage
            self.defi_data_verified.write(user.into(), true.into());
            self.last_defi_update.write(user.into(), timestamp.into());
            
            // Update rate limiting
            let day = timestamp / 86400;
            let current_count = self.submission_count.read((provider, day));
            self.submission_count.write((provider, day), current_count + 1);
            
            // Emit event
            self.emit(Event::DataSubmitted(
                DataSubmitted {
                    provider,
                    user,
                    data_type: 'DEFI_DATA',
                    timestamp
                }
            ));
            
            true
        }

        fn submit_exchange_data(
            ref self: ContractState,
            user: ContractAddress,
            data: ExchangeData
        ) -> bool {
            self._check_provider_authorization();
            self._enforce_rate_limit();
            
            let provider = get_caller_address();
            let timestamp = get_block_timestamp();
            
            // Validate data
            self._validate_exchange_data(@data);
            
            // Update storage
            self.exchange_data_verified.write(user.into(), true.into());
            self.last_exchange_update.write(user.into(), timestamp.into());
            
            // Update rate limiting
            let day = timestamp / 86400;
            let current_count = self.submission_count.read((provider, day));
            self.submission_count.write((provider, day), current_count + 1);
            
            // Emit event
            self.emit(Event::DataSubmitted(
                DataSubmitted {
                    provider,
                    user,
                    data_type: 'EXCHANGE_DATA',
                    timestamp
                }
            ));
            
            true
        }

        fn verify_data_submission(
            self: @ContractState,
            user: ContractAddress
        ) -> VerificationData {
            let contract_address = get_contract_address();
            let timestamp = get_block_timestamp();
            
            // Create verification data
            VerificationData {
                data_hash: self._calculate_verification_hash(user),
                verification_time: timestamp,
                verifier: contract_address
            }
        }

        fn get_verification_status(
            self: @ContractState,
            user: ContractAddress
        ) -> u8 {
            let mut status = 0;
            
            if self.wallet_data_verified.read(user) {
                status += 1;
            }
            if self.defi_data_verified.read(user) {
                status += 2;
            }
            if self.exchange_data_verified.read(user) {
                status += 4;
            }
            
            status
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _check_provider_authorization(self: @ContractState) {
            let caller = get_caller_address();
            assert(
                self.authorized_providers.read(caller),
                Errors::INSUFFICIENT_PERMISSION
            );
        }

        fn _enforce_rate_limit(self: @ContractState) {
            let _caller = get_caller_address();
            let _timestamp = get_block_timestamp();
            let _day = _timestamp / 86400;
            let current_count = self.submission_count.read((_caller.into(), _day.into()));
            assert(
                current_count < self.max_daily_submissions.read().into(),
                Errors::RATE_LIMIT_EXCEEDED
            );
        }
        fn _validate_wallet_data(self: @ContractState, data: @WalletData) {
            assert(*data.balance >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(*data.transaction_count >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(
                *data.last_transaction_time >= *data.first_transaction_time,
                Errors::INVALID_PARAMETERS
            );
        }
        fn _validate_defi_data(self: @ContractState, data: @DefiData) {
            assert(*data.total_value_locked >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(*data.protocol_interactions >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(*data.unique_protocols >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(
                *data.last_interaction >= *data.first_interaction,
                Errors::INVALID_PARAMETERS
            );
        }

        fn _validate_exchange_data(self: @ContractState, data: @ExchangeData) {
            assert(*data.trading_volume >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(*data.successful_trades >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(*data.failed_trades >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(*data.liquidations >= 0_u256, Errors::INVALID_PARAMETERS);
            assert(
                *data.last_trade >= *data.first_trade,
                Errors::INVALID_PARAMETERS
            );
        }

        fn _calculate_verification_hash(self: @ContractState, user: ContractAddress) -> felt252 {
            // Combine all verification statuses and timestamps
            let wallet_verified: bool = self.wallet_data_verified.read(user);
            let defi_verified: bool = self.defi_data_verified.read(user);
            let exchange_verified: bool = self.exchange_data_verified.read(user);
            let wallet_timestamp: u64 = self.last_wallet_update.read(user);
            let defi_timestamp: u64 = self.last_defi_update.read(user);
            let exchange_timestamp: u64 = self.last_exchange_update.read(user);
            // Create a composite hash
            let user_felt: felt252 = user.into();
            let wallet_felt: felt252 = wallet_verified.into();
            let defi_felt: felt252 = defi_verified.into();
            let exchange_felt: felt252 = exchange_verified.into();
            let wallet_time_felt: felt252 = wallet_timestamp.into();
            let defi_time_felt: felt252 = defi_timestamp.into();
            let exchange_time_felt: felt252 = exchange_timestamp.into();

            let hash0: felt252 = LegacyHash::hash(user_felt, wallet_felt);
            let hash1: felt252 = LegacyHash::hash(hash0, defi_felt);
            let hash2: felt252 = LegacyHash::hash(hash1, exchange_felt);
            let hash3: felt252 = LegacyHash::hash(hash2, wallet_time_felt);
            let hash4: felt252 = LegacyHash::hash(hash3, defi_time_felt);
            let final_hash: felt252 = LegacyHash::hash(hash4, exchange_time_felt);
            
            final_hash
        }
    }
}