use starknet::{ContractAddress, get_block_timestamp};
use super::data_structures::{WalletData, DefiData, ExchangeData, CreditScore, ScoreFactors, Constants};
use starknet::storage::{StoragePointerWriteAccess, Map};

#[starknet::interface]
pub trait IScoringEngine<TContractState> {
    // Core scoring functions
    fn calculate_credit_score(
        ref self: TContractState,
        wallet_data: WalletData,
        defi_data: DefiData,
        exchange_data: ExchangeData
    ) -> CreditScore;

    fn get_score_factors(self: @TContractState, user: ContractAddress) -> ScoreFactors;
    
    // Configuration functions
    fn update_score_weights(ref self: TContractState, new_weights: ScoreFactors);
    fn set_minimum_requirements(
        ref self: TContractState, 
        min_age: u64,
        min_tx: u256,
        min_defi: u256
    );
}

#[starknet::contract]
pub mod ScoringEngine {
    use starknet::storage::StoragePointerReadAccess;
use starknet::storage::{StorageMapWriteAccess};
    use super::*;
    use starknet::{ContractAddress, get_caller_address};
        const INSUFFICIENT_PERMISSION: felt252 = 'Insufficient permission';
        const INVALID_PARAMETERS: felt252 = 'Invalid parameters';
        const INSUFFICIENT_DATA: felt252 = 'Insufficient data';
    

    #[storage]
    struct Storage {
        // Scoring configuration
        score_weights: ScoreFactors,
        min_account_age: u64,
        min_transactions: u256,
        min_defi_interactions: u256,
        
        // Admin controls
        admin: ContractAddress,
        is_initialized: bool,
        
        // Cached calculations
        cached_scores: Map<ContractAddress, CreditScore>,
        calculation_timestamps: Map<ContractAddress, u64>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ScoreCalculated: ScoreCalculated,
        WeightsUpdated: WeightsUpdated,
        RequirementsUpdated: RequirementsUpdated
    }

    #[derive(Drop, starknet::Event)]
    struct ScoreCalculated {
        user: ContractAddress,
        score: u256,
        confidence: u8,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct WeightsUpdated {
        old_weights: ScoreFactors,
        new_weights: ScoreFactors,
        updated_by: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct RequirementsUpdated {
        min_age: u64,
        min_tx: u256,
        min_defi: u256,
        updated_by: ContractAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress) {
        self.admin.write(admin_address);
        self._initialize_default_weights();
        self._initialize_default_requirements();
    }

    #[abi(embed_v0)]
    impl ScoringEngine of super::IScoringEngine<ContractState> {
        fn calculate_credit_score(
            ref self: ContractState,
            wallet_data: WalletData,
            defi_data: DefiData,
            exchange_data: ExchangeData
        ) -> CreditScore {
            // Validate input data
            self._validate_input_data(@wallet_data, @defi_data, @exchange_data);
            
            // Calculate individual components
            let wallet_score = self._calculate_wallet_score(@wallet_data);
            let defi_score = self._calculate_defi_score(@defi_data);
            let exchange_score = self._calculate_exchange_score(@exchange_data);
            let longevity_score = self._calculate_longevity_score(
                wallet_data.first_transaction_time,
                defi_data.first_interaction,
                exchange_data.first_trade
            );
            
            // Calculate confidence level
            let confidence = self._calculate_confidence_level(
                @wallet_data,
                @defi_data,
                @exchange_data
            );
            
            // Combine scores with weights
            let weights = self.score_weights.read();
            let final_score = self._combine_weighted_scores(
                wallet_score,
                defi_score,
                exchange_score,
                longevity_score,
                @weights
            );
            
            // Create and cache result
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            
            let credit_score = CreditScore {
                score: final_score,
                last_update: timestamp,
                confidence_level: confidence,
                data_completeness: self._calculate_data_completeness(
                    @wallet_data,
                    @defi_data,
                    @exchange_data
                )
            };
            
            self.cached_scores.write(caller, credit_score);
            self.calculation_timestamps.write(caller, timestamp);
            
            self.emit(Event::ScoreCalculated(
                ScoreCalculated {
                    user: caller,
                    score: final_score,
                    confidence: confidence,
                    timestamp: timestamp
                }
            ));
            
            credit_score
        }

        fn get_score_factors(self: @ContractState, user: ContractAddress) -> ScoreFactors {
            self.score_weights.read()
        }

        fn update_score_weights(ref self: ContractState, new_weights: ScoreFactors) {
            // Only admin can update weights
            let caller = get_caller_address();
            assert(caller == self.admin.read(), INSUFFICIENT_PERMISSION);
            
            // Validate weights sum to 100
            assert(
                new_weights.wallet_weight +
                new_weights.defi_weight +
                new_weights.exchange_weight +
                new_weights.longevity_weight +
                new_weights.stability_weight == 100,
                INVALID_PARAMETERS
            );

            let old_weights = self.score_weights.read();
            self.score_weights.write(new_weights);
            
            self.emit(Event::WeightsUpdated(
                WeightsUpdated {
                    old_weights,
                    new_weights,
                    updated_by: caller
                }
            ));
        }

        fn set_minimum_requirements(
            ref self: ContractState,
            min_age: u64,
            min_tx: u256,
            min_defi: u256
        ) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), INSUFFICIENT_PERMISSION);
            
            self.min_account_age.write(min_age);
            self.min_transactions.write(min_tx);
            self.min_defi_interactions.write(min_defi);
            
            self.emit(Event::RequirementsUpdated(
                RequirementsUpdated {
                    min_age,
                    min_tx,
                    min_defi,
                    updated_by: caller
                }
            ));
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _initialize_default_weights(ref self: ContractState) {
            if !self.is_initialized.read() {
                self.score_weights.write(ScoreFactors {
                    wallet_weight: Constants::WALLET_WEIGHT,
                    defi_weight: Constants::DEFI_WEIGHT,
                    exchange_weight: Constants::EXCHANGE_WEIGHT,
                    longevity_weight: Constants::LONGEVITY_WEIGHT,
                    stability_weight: Constants::STABILITY_WEIGHT
                });
                self.is_initialized.write(true);
            }
        }

        fn _initialize_default_requirements(ref self: ContractState) {
            self.min_account_age.write(Constants::MIN_ACCOUNT_AGE_DAYS);
            self.min_transactions.write(Constants::MIN_TRANSACTIONS);
            self.min_defi_interactions.write(Constants::MIN_DEFI_INTERACTIONS);
        }

        fn _validate_input_data(
            self: @ContractState,
            wallet_data: @WalletData,
            defi_data: @DefiData,
            exchange_data: @ExchangeData
        ) {
            // Ensure minimum data requirements are met
            let current_time = get_block_timestamp();
            let account_age = current_time - *wallet_data.first_transaction_time;
            
            assert(
                account_age >= self.min_account_age.read(),
                INSUFFICIENT_DATA
            );
            
            assert(
                *wallet_data.transaction_count >= self.min_transactions.read(),
                INSUFFICIENT_DATA
            );
            
            assert(
                *defi_data.protocol_interactions >= self.min_defi_interactions.read(),
                INSUFFICIENT_DATA
            );
        }

        // Individual scoring components
        fn _calculate_wallet_score(self: @ContractState, data: @WalletData) -> u256 {
            // Sophisticated wallet scoring logic
            let mut score = 0;
            
            // Balance score (up to 40 points)
            score += if *data.balance > 100_000_000_000_000_000_000 { // 100 ETH
                40
            } else if *data.balance > 10_000_000_000_000_000_000 { // 10 ETH
                30
            } else if *data.balance > 1_000_000_000_000_000_000 { // 1 ETH
                20
            } else {
                10
            };
            
            // Transaction activity (up to 60 points)
            score += if *data.transaction_count > 1000 {
                60
            } else if *data.transaction_count > 100 {
                45
            } else if *data.transaction_count > 50 {
                30
            } else {
                15
            };
            
            score
        }

        fn _calculate_defi_score(self: @ContractState, data: @DefiData) -> u256 {
            let mut score = 0;
            
            // TVL score (up to 40 points)
            score += if *data.total_value_locked > 100_000_000_000_000_000_000 {
                40
            } else if *data.total_value_locked > 10_000_000_000_000_000_000 {
                30
            } else if *data.total_value_locked > 1_000_000_000_000_000_000 {
                20
            } else {
                10
            };
            
            // Protocol diversity (up to 30 points)
                score += if *data.unique_protocols > 10 {
                    30
                } else if *data.unique_protocols > 5 {
                    20
                } else {
                    10
                };
    
                // Interaction frequency (up to 30 points)
                score += if *data.protocol_interactions > 100 {
                    30
                } else if *data.protocol_interactions > 50 {
                    20
                } else {
                    10
                };
                
                score
            }
    
            fn _calculate_exchange_score(self: @ContractState, data: @ExchangeData) -> u256 {
                let mut score = 0;
                
                // Trading volume (up to 40 points)
                score += if *data.trading_volume > 1000_000_000_000_000_000_000 {
                    40
                } else if *data.trading_volume > 100_000_000_000_000_000_000 {
                    30
                } else if *data.trading_volume > 10_000_000_000_000_000_000 {
                    20
                } else {
                    10
                };
                
                // Success rate (up to 40 points)
                let total_trades = *data.successful_trades + *data.failed_trades;
                if total_trades > 0 {
                    let success_rate = (*data.successful_trades * 100) / total_trades;
                    score += if success_rate > 95 {
                        40
                    } else if success_rate > 90 {
                        30
                    } else if success_rate > 80 {
                        20
                    } else {
                        10
                    };
                }
                
                // Liquidation penalty (up to -30 points)
                let liquidation_penalty = if *data.liquidations > 5 {
                    30
                } else if *data.liquidations > 2 {
                    20
                } else if *data.liquidations > 0 {
                    10
                } else {
                    0
                };
                
                if score > liquidation_penalty {
                    score - liquidation_penalty
                } else {
                    0
                }
            }
    
            fn _calculate_longevity_score(
                self: @ContractState,
                wallet_start: u64,
                defi_start: u64,
                exchange_start: u64
            ) -> u256 {
                let current_time = get_block_timestamp();
                let earliest_activity = min(wallet_start, min(defi_start, exchange_start));
                let account_age_days = (current_time - earliest_activity) / 86400; // Convert to days
                
                if account_age_days > 365 { // More than 1 year
                    100
                } else if account_age_days > 180 { // More than 6 months
                    75
                } else if account_age_days > 90 { // More than 3 months
                    50
                } else {
                    25
                }
            }
    
            fn _calculate_confidence_level(
                self: @ContractState,
                wallet_data: @WalletData,
                defi_data: @DefiData,
                exchange_data: @ExchangeData
            ) -> u8 {
                let mut confidence = 0;
                
                // Data completeness
                confidence += if *wallet_data.transaction_count > 0 { 25 } else { 0 };
                confidence += if *defi_data.protocol_interactions > 0 { 25 } else { 0 };
                confidence += if *exchange_data.trading_volume > 0 { 25 } else { 0 };
                
                // Data recency
                let current_time = get_block_timestamp();
                let data_age = current_time - max(
                    *wallet_data.last_transaction_time,
                    max(*defi_data.last_interaction, *exchange_data.last_trade)
                );
                
                confidence += if data_age < 604800 { // Within 1 week
                    25
                } else if data_age < 2592000 { // Within 1 month
                    15
                } else if data_age < 7776000 { // Within 3 months
                    10
                } else {
                    0
                };
                
                confidence
            }
    
            fn _calculate_data_completeness(
                self: @ContractState,
                wallet_data: @WalletData,
                defi_data: @DefiData,
                exchange_data: @ExchangeData
            ) -> u8 {
                let mut completeness = 0;
                
                // Wallet data completeness
                if *wallet_data.transaction_count > 0 {
                    completeness += 40;
                }
                
                // DeFi data completeness
                if *defi_data.protocol_interactions > 0 {
                    completeness += 30;
                }
                
                // Exchange data completeness
                if *exchange_data.trading_volume > 0 {
                    completeness += 30;
                }
                
                completeness
            }
    
            fn _combine_weighted_scores(
                self: @ContractState,
                wallet_score: u256,
                defi_score: u256,
                exchange_score: u256,
                longevity_score: u256,
                weights: @ScoreFactors
            ) -> u256 {
                let base_score = Constants::MIN_SCORE;
                
                let weighted_sum = 
                    (wallet_score * (*weights).wallet_weight.into()) +
                    (defi_score * (*weights).defi_weight.into()) +
                    (exchange_score * (*weights).exchange_weight.into()) +
                    (longevity_score * (*weights).longevity_weight.into());
                
                let max_weighted_score = Constants::MAX_SCORE - Constants::MIN_SCORE;
                let actual_weighted_score = (weighted_sum * max_weighted_score) / (100 * 100);
                
                base_score + actual_weighted_score
            }
        }
    }
    
    // Helper functions
    fn min(a: u64, b: u64) -> u64 {
        if a < b { a } else { b }
    }
    
    fn max(a: u64, b: u64) -> u64 {
        if a > b { a } else { b }
    }