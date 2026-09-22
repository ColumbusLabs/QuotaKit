package enum MistralTokenMath {
    package static func total(input: Int, cached: Int, output: Int) -> Int? {
        let lanes = [input, cached, output].sorted()
        // Opposite-sign extremes cancel safely; same-sign overflow cannot be canceled by the middle lane.
        let first = lanes[0].addingReportingOverflow(lanes[2])
        guard !first.overflow else { return nil }
        let second = first.partialValue.addingReportingOverflow(lanes[1])
        guard !second.overflow else { return nil }
        return second.partialValue
    }

    package static func sum(_ values: [Int]) -> Int? {
        var total = 0
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }
}
