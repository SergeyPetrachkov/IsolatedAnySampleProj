import Foundation
import IsolatedAnySampleProj
import Testing

struct ImageCacheItem: Equatable {
	let imageData: Image
}

struct Image: Equatable {
	let data: Data
}

protocol ImageLoader {
	func load(url: URL, item: ImageCacheItem, completion: @escaping @MainActor (ImageCacheItem, Image?) -> Void)
	func loadNonIsolated(url: URL, item: ImageCacheItem, nonIsolatedCompletion: @escaping @Sendable (ImageCacheItem, Image?) -> Void)
}

final class MockImageLoader: ImageLoader, @unchecked Sendable {

	typealias LoadUrlItemCompletionInput = (
		url: URL,
		item: ImageCacheItem
	)

	let loadUrlWithCompletionMock = MockFunc<LoadUrlItemCompletionInput, (ImageCacheItem, Image?)>()
	func load(url: URL, item: ImageCacheItem, completion: @escaping @MainActor @Sendable (ImageCacheItem, Image?) -> Void) {
		loadUrlWithCompletionMock.callAndReturn((url, item), completion: completion)
	}

	let loadUrlWithNonIsolatedCompletionMock = MockFunc<LoadUrlItemCompletionInput, (ImageCacheItem, Image?)>()
	func loadNonIsolated(url: URL, item: ImageCacheItem, nonIsolatedCompletion: @escaping @Sendable (ImageCacheItem, Image?) -> Void) {
		loadUrlWithNonIsolatedCompletionMock.callAndReturn((url, item), completion: nonIsolatedCompletion)
	}
}

struct RegularMockFuncTests {

	@Test(.testEnvironment)
	@MainActor
	func regularMockFuncWithCompletionGetsCalled() {
		let env = Environment.current
		let sut = env.makeSUT()

		var completionCallsCount = 0
		// we actually prove that MockFunc flattens async completions to sync code,
		// as the checks within this closure will be done synchronously before the test finishes
		let completion: @MainActor @Sendable (ImageCacheItem, Image?) -> Void = { cacheItem, image in
			completionCallsCount += 1
			#expect(cacheItem == env.sampleCachedImage)
			#expect(image == env.sampleImage)
		}

		sut.load(url: env.sampleURL, item: env.sampleCachedImage, completion: completion)

		#expect(sut.loadUrlWithCompletionMock.called)
		#expect(sut.loadUrlWithCompletionMock.calledOnce)
		#expect(sut.loadUrlWithCompletionMock.input == (url: env.sampleURL, item: env.sampleCachedImage))
		#expect(sut.loadUrlWithCompletionMock.output == (env.sampleCachedImage, env.sampleImage))
		#expect(sut.loadUrlWithCompletionMock.completions.count == 1)
		#expect(completionCallsCount == 1)
	}

	@Test(.testEnvironment)
	func regularMockFuncWithNonIsolatedCompletionGetsCalled() async {
		let env = Environment.current
		let sut = env.makeSUT()

		nonisolated(unsafe) var completionCallsCount = 0
		// we actually prove that MockFunc flattens async completions to sync code,
		// as the checks within this closure will be done synchronously before the test finishes
		let completion: @Sendable (ImageCacheItem, Image?) -> Void = { cacheItem, image in
			completionCallsCount += 1
			#expect(cacheItem == env.sampleCachedImage)
			#expect(image == env.sampleImage)
		}
		sut.loadNonIsolated(url: env.sampleURL, item: env.sampleCachedImage, nonIsolatedCompletion: completion)

		#expect(sut.loadUrlWithNonIsolatedCompletionMock.called)
		#expect(sut.loadUrlWithNonIsolatedCompletionMock.calledOnce)
		#expect(sut.loadUrlWithNonIsolatedCompletionMock.input == (url: env.sampleURL, item: env.sampleCachedImage))
		#expect(sut.loadUrlWithNonIsolatedCompletionMock.output == (env.sampleCachedImage, env.sampleImage))
		#expect(sut.loadUrlWithNonIsolatedCompletionMock.completions.count == 1)
		#expect(completionCallsCount == 1)
	}
}

struct Environment {
	let sampleImage: Image
	let sampleCachedImage: ImageCacheItem
	let sampleURL: URL

	init() {
		// set up sample Data
		sampleImage = Image(data: Data())
		sampleCachedImage = ImageCacheItem(imageData: sampleImage)
		sampleURL = URL(string: "https://sample-link.com")!
	}

	func makeSUT() -> MockImageLoader {
		let sut = MockImageLoader()
		// set up mocks
		sut.loadUrlWithCompletionMock.returns((sampleCachedImage, sampleImage))
		sut.loadUrlWithNonIsolatedCompletionMock.returns((sampleCachedImage, sampleImage))
		return sut
	}
}

// test traits to reduce boilerplate
extension Environment {
	@TaskLocal static var current = Environment()
}

struct TestEnvironment: TestTrait, SuiteTrait, TestScoping {
	func provideScope(
		for test: Test,
		testCase: Test.Case?,
		performing function: @Sendable () async throws -> Void
	) async throws {
		try await Environment.$current.withValue(Environment()) {
			try await function()
		}
	}
}

extension Trait where Self == TestEnvironment {
	static var testEnvironment: Self { Self() }
}
