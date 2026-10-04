import Foundation

// Small helpers shared by the assessors, so the squat, push-up, pull-up and dip assessors word their findings the same way.

/// "87°"
func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

func average(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
