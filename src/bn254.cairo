// use core::zeroable::NonZero;
// use core::traits::DivRem;
use core::option::OptionTrait;
// use core::array::ArrayTrait;
// use core::traits::Into;
use core::option::Option;

// Constants for BN254 curve
const BN254_ORDER: u256 = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001_u256;
const BN254_A: u256 = 0_u256;
const BN254_B: u256 = 3_u256;

#[derive(Copy, Drop, Serde)]
struct BN254Point {
    x: u256,
    y: u256,
}

#[derive(Copy, Drop, Serde)]
struct BN254G2Point {
    x: (u256, u256),
    y: (u256, u256),
}

trait BN254Trait {
    fn is_on_curve(self: @BN254Point) -> bool;
    fn add(self: @BN254Point, other: @BN254Point) -> BN254Point;
    fn scalar_mul(self: @BN254Point, scalar: u256) -> BN254Point;
    fn negate(self: @BN254Point) -> BN254Point;
    fn double(self: @BN254Point) -> BN254Point;
    fn is_infinity(self: @BN254Point) -> bool;
    fn mul_by_cofactor(self: @BN254Point) -> BN254Point;
}

impl BN254PointImpl of BN254Trait {
    fn is_on_curve(self: @BN254Point) -> bool {
        let y2 = (*self.y * *self.y) % BN254_ORDER;
        let x3 = ((*self.x * *self.x * *self.x) + BN254_B) % BN254_ORDER;
        y2 == x3
    }

    fn add(self: @BN254Point, other: @BN254Point) -> BN254Point {
        if self.is_infinity() {
            return *other;
        }
        if other.is_infinity() {
            return *self;
        }

        if *self.x == *other.x && (*self.y != *other.y || *self.y == 0_u256) {
            return BN254Point { x: 0_u256, y: 0_u256 };
        }

        let slope = if *self.x == *other.x {
            (3_u256 * *self.x * *self.x) * mod_inverse((2_u256 * *self.y) % BN254_ORDER).unwrap()
        } else {
            (*other.y - *self.y) * mod_inverse((*other.x - *self.x) % BN254_ORDER).unwrap()
        } % BN254_ORDER;

        let x3 = (slope * slope - *self.x - *other.x) % BN254_ORDER;
        let y3 = (slope * (*self.x - x3) - *self.y) % BN254_ORDER;

        BN254Point { x: x3, y: y3 }
    }

    fn scalar_mul(self: @BN254Point, scalar: u256) -> BN254Point {
        let mut result = BN254Point { x: 0_u256, y: 0_u256 };
        let mut temp = *self;
        let mut current_scalar = scalar;

        while current_scalar != 0_u256 {
            if current_scalar % 2_u256 != 0_u256 {
                result = Self::add(@result, @temp);
            }
            temp = Self::double(@temp);
            current_scalar /= 2_u256;
        };

        result
    }

    fn double(self: @BN254Point) -> BN254Point {
        if self.is_infinity() {
            return *self;
        }

        let slope = (3_u256 * *self.x * *self.x) * mod_inverse((2_u256 * *self.y) % BN254_ORDER).unwrap() % BN254_ORDER;
        let x3 = (slope * slope - 2_u256 * *self.x) % BN254_ORDER;
        let y3 = (slope * (*self.x - x3) - *self.y) % BN254_ORDER;

        BN254Point { x: x3, y: y3 }
    }

    fn negate(self: @BN254Point) -> BN254Point {
        BN254Point { x: *self.x, y: BN254_ORDER - *self.y }
    }

    fn is_infinity(self: @BN254Point) -> bool {
        *self.x == 0_u256 && *self.y == 0_u256
    }

    fn mul_by_cofactor(self: @BN254Point) -> BN254Point {
        self.scalar_mul(1_u256)
    }
}

// Helper functions
fn mod_inverse(a: u256) -> Option<u256> {
    let mut t = 0_u256;
    let mut new_t = 1_u256;
    let mut r = BN254_ORDER;
    let mut new_r = a;

    while new_r != 0_u256 {
        let quotient = r / new_r;
        t = new_t;
        new_t = t - quotient * new_t;
        r = new_r;
        new_r = r - quotient * new_r;
    };

    if r > 1_u256 {
        return Option::None;
    }

    if t < 0_u256 {
        t += BN254_ORDER;
    }

    Option::Some(t)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_point_addition() {
        let p1 = BN254Point { x: 1_u256, y: 2_u256 };
        let p2 = BN254Point { x: 2_u256, y: 3_u256 };
        let result = BN254Trait::add(@p1, @p2);
        assert!(BN254Trait::is_on_curve(@result));
    }

    #[test]
    fn test_point_doubling() {
        let p = BN254Point { x: 1_u256, y: 2_u256 };
        let result = BN254Trait::double(@p);
        assert!(BN254Trait::is_on_curve(@result));
    }
}
