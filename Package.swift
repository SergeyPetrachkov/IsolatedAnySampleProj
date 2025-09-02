// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
	name: "IsolatedAnySampleProj",
	platforms: [.iOS(.v13), .macOS(.v12), .watchOS(.v10)],
	products: [
		.library(
			name: "IsolatedAnySampleProj",
			targets: ["IsolatedAnySampleProj"]
		),
	],
	targets: [
		.target(
			name: "IsolatedAnySampleProj",
			swiftSettings: swiftSettings
		),
		.testTarget(
			name: "IsolatedAnySampleProjTests",
			dependencies: ["IsolatedAnySampleProj"],
			swiftSettings: swiftSettings
		),
	]
)
