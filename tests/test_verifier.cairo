// #[cfg(test)]
// mod tests {
//     use core::array::SpanTrait;
//     use crate::verifier::ZkCredScoreVerifier;
//     use starknet::ContractAddress;
//     use starknet::testing::{set_caller_address, set_block_timestamp};
//     use core::test::test_utils::assert_eq;

//     fn setup() -> (ContractAddress, ContractAddress) {
//         let admin = contract_address_const::<1>();
//         let user = contract_address_const::<2>();
//         (admin, user)
//     }

//     #[test]
//     fn test_proof_verification() {
//         let (admin, user) = setup();
//         let mut state = ZkCredScoreVerifier::contract_state_for_testing();
        
//         let vk = (0x1234_felt252, 0x5678_felt252);
//         ZkCredScoreVerifier::constructor(ref state, admin, vk);

//         set_caller_address(user);
//         set_block_timestamp(1000);

//         let proof_a = (0x1234_felt252, 0x5678_felt252);
//         let proof_b = ((0x1234_felt252, 0x5678_felt252), (0x9abc_felt252, 0xdef0_felt252));
//         let proof_c = (0x4321_felt252, 0x8765_felt252);

//         let mut inputs = array![750_felt252];
//         let result = ZkCredScoreVerifier::verify_proof(
//             ref state, proof_a, proof_b, proof_c, inputs.span()
//         );

//         assert(result, 'Proof verification failed');
//         let score = ZkCredScoreVerifier::get_credit_score(@state, user);
//         assert(score == 750_u256, 'Wrong credit score');
//     }

//     #[test]
//     fn test_multiple_users() {
//         let (admin, user1) = setup();
//         let user2 = contract_address_const::<3>();
//         let mut state = ZkCredScoreVerifier::contract_state_for_testing();
        
//         let vk = (0x1234_felt252, 0x5678_felt252);
//         ZkCredScoreVerifier::constructor(ref state, admin, vk);

//         // Test first user
//         set_caller_address(user1);
//         let mut inputs1 = array![750_felt252];
//         ZkCredScoreVerifier::verify_proof(
//             ref state,
//             (0x1_felt252, 0x2_felt252),
//             ((0x3_felt252, 0x4_felt252), (0x5_felt252, 0x6_felt252)),
//             (0x7_felt252, 0x8_felt252),
//             inputs1.span()
//         );

//         // Test second user
//         set_caller_address(user2);
//         let mut inputs2 = array![800_felt252];
//         ZkCredScoreVerifier::verify_proof(
//             ref state,
//             (0x9_felt252, 0xa_felt252),
//             ((0xb_felt252, 0xc_felt252), (0xd_felt252, 0xe_felt252)),
//             (0xf_felt252, 0x10_felt252),
//             inputs2.span()
//         );

//         assert(ZkCredScoreVerifier::get_credit_score(@state, user1) == 750_u256, 'Wrong score user1');
//         assert(ZkCredScoreVerifier::get_credit_score(@state, user2) == 800_u256, 'Wrong score user2');
//     }
// }