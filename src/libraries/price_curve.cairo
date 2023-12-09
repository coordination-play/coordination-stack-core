mod PriceCurve {
    use integer::u256_sqrt;

    const PRECISION: u256 = 100000000;
    const PRECISION_SQRT: u256 = 10000;

    // Curve eq = a * sqrt(x) + b, Curve = {a,b}
    fn get_price(a: u32, b: u32, start_point: u256, shares: u256) -> u256 {
        let end_point = start_point + shares;
        let start_point_sqrt = u256 { low: u256_sqrt(start_point * PRECISION), high: 0 };
        let end_point_sqrt = u256 { low: u256_sqrt(end_point * PRECISION), high: 0 };
        (b.into() * PRECISION_SQRT)  + (2*a.into() *(end_point*end_point_sqrt - start_point*start_point_sqrt) / (3*shares))
    }
}