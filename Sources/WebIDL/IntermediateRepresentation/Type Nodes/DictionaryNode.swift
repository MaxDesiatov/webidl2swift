//
//  Created by Manuel Burghard. Licensed unter MIT.
//

import Foundation

class DictionaryNode: TypeNode, Equatable {

    let typeName: String
    var inheritsFrom: NodePointer?
    var members: [String]

    internal init(typeName: String, inheritsFrom: NodePointer?, members: [String]) {
        self.typeName = typeName
        self.inheritsFrom = inheritsFrom
        self.members = members
    }

    var isDictionary: Bool {
        true
    }

    var swiftTypeName: String {
        typeName
    }

    var cases: [String] {

        if let baseNode = inheritsFrom?.node {
            guard let baseDictionaryNode = baseNode as? DictionaryNode else {
                fatalError("Expected Dictionary as base of other Dictionary")
            }

            struct Ordered<Element: Hashable>: Hashable {

                static func == (lhs: Ordered<Element>, rhs: Ordered<Element>) -> Bool {
                    lhs.value == rhs.value
                }

                let value: Element
                let index: Int

                func hash(into hasher: inout Hasher) {
                    hasher.combine(value)
                }
            }
            var counter = 0
            var orderedSet = Set<Ordered<String>>(baseDictionaryNode.cases.map { let ordered = Ordered(value: $0, index: counter); counter += 1; return ordered })
            orderedSet.formUnion(members.map { let ordered = Ordered(value: $0, index: counter); counter += 1; return ordered })

            return orderedSet
                .sorted { $0.index < $1.index }
                .map { $0.value }
        } else {
            return members
        }
    }

    var swiftDeclaration: String {

        let cases = self.cases

        return """
        public struct \(swiftTypeName): ExpressibleByDictionaryLiteral, JSValueCodable {

            public static func canDecode(from jsValue: JSValue) -> Bool {
                return jsValue.isObject
            }

            public enum Key: String, Hashable {

                case \(cases.map(escapedName).joined(separator: ", "))
            }

            public typealias Value = AnyJSValueCodable

            private let dictionary: [String : AnyJSValueCodable]

            public init(uniqueKeysWithValues elements: [(Key, Value)]) {
                self.dictionary = Dictionary(uniqueKeysWithValues: elements.map({ ($0.0.rawValue, $0.1) }))
            }

            public init(dictionaryLiteral elements: (Key, AnyJSValueCodable)...) {
                self.dictionary = Dictionary(uniqueKeysWithValues: elements.map({ ($0.0.rawValue, $0.1) }))
            }

            subscript(_ key: Key) -> AnyJSValueCodable? {
                dictionary[key.rawValue]
            }

            public init(jsValue: JSValue) {

                self.dictionary = jsValue.fromJSValue()
            }

            public func jsValue() -> JSValue {
                return dictionary.jsValue()
            }
        }
        """
    }

    func typeCheck(withArgument argument: String) -> String {
        "case .object = \(argument)"
    }

    static func == (lhs: DictionaryNode, rhs: DictionaryNode) -> Bool {
        lhs.typeName == rhs.typeName
    }
}
