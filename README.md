# IsolatedAnySampleProj

## The goal

The goal is to demonstrate a possible issue (or rather a limitation) when using `isolated(any)` feature of the Swift language.

## Requirements

Xcode 26 beta or any other IDE of choice with Swift 6.2 on board.

## Description

In this project there's a small part of a testing framework that is used by a large team in a big project. The idea is to use generics to make it easier to mock protocols.
`MockFunc` represents a container that observers and records a function behavior. So, if we have a protocol that has a function, and we want to know how many times the function was called and with what arguments, we use `MockFunc<Input, Output>`.
In Tests target you can find an example of how a protocol is mocked and how the framework is used in tests. The most important part of MockFunc is that it helps developers to flatten out async tests for the closure-based APIs.

### Problem

With introduction of Swift Concurrency we've got a concept of isolation and isolation domains, which can be applied not only to types, but also to closures, so it is possible to have a function like this:

```Swift
func loadData(completion: @MainActor @escaping (Data) -> Void) {}
```

and it will be a different function than:
```Swift
func loadData(completion: @escaping (Data) -> Void) {}
```

(It's out of scope whether or not such APIs should exist at all)

To be able to test and to mock both types of functions, I assumed that `isolated(any)` could be a nice fit. So, the MockFunc has this:

```Swift
public func callAndReturn(
		_ input: Input,
		completion: @escaping @isolated(any) (Output) -> Void
	) {
		call(with: input)
		let completionContainer = CompletionContainer(completion: completion)
		completions.append(completionContainer)
		if callsCompletionImmediately {
			completionContainer(output)
		}
}
```

while the CompletionContainer looks like this:

```Swift
public struct CompletionContainer<Output> {

	let completion: (Output) -> Void

	@inline(__always)
	public func callAsFunction(_ output: Output) {
		completion(output)
	}
}
```

An example of a mock:

```Swift
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
```

An example of a test:
```Swift
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
```

However, in Swift 6.2 it gives the following warning:

**Converting @isolated(any) function of type '@isolated(any) (Output) -> Void' to synchronous function type '(Output) -> Void' is not allowed; this will be an error in a future Swift language mode**

If I check the source codes of Swift, it looks like the isolation becomes a part of a type, which is ok, but introduces some limitations.

Right now the code compiles and allows to execute the completions synchronously, but I guess this will break in Swift 6.3 or Swift 7.

Since, it's a testing framework and synchronous execution is crucial, I thought we could use the same as `MainActor.assumeIsolated`, because we have the `isolation` property like this:

```Swift
let actor = completion.isolation
actor?.assumeIsolated { _ in
	completion(output)
}
```

while it's unsafe, the goal is worth it, especially inwithin the testing scenarios. 
Unfortunately, it's not possible. It gives the following error: **Call to @isolated(any) parameter 'completion' in a synchronous actor-isolated context**
which is conceptually correct, but as with `MainActor.assumeIsolated` I expected this to be a solution to execute potentially unsafe code.

So, I have a few questions:

* will we get a way to `assumeIsolated` the same way we have now with the MainActor?
* is there any other way to achieve my goal (synchronous execution of closures regardless of isolation) besides creating another `GlobalActorIsolatedMockFunc` type per global actor in my project?
