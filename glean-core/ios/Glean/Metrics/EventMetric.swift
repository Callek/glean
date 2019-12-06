/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Deserialized event data.
public struct RecordedEventData {
    /// The event's category, part of the full identifier
    let category: String
    /// The event's name, part of the full identifier
    let name: String
    /// The event's timestamp
    let timestamp: UInt64
    /// Any extra data recorded for the event
    let extra: [String: String]?

    var identifier: String {
        if category.isEmpty {
            return name
        } else {
            return "\(category).\(name)"
        }
    }
}

/// Extra keys for events.
/// Extra keys can be of any type, but need to adhere to a protocol.
///
/// For user-defined `EventMetricType`s these will be defined as `enums`.
public protocol ExtraKeys: Hashable {
    /// The index of the extra key, used to index the string array passed at `EventMetricType` instantiation.
    func index() -> Int32
}

/// Default of no extra keys for events.
///
/// An enum with no values for convenient use as the default set of extra keys
/// that an `EventMetricType` can accept.
public enum NoExtraKeys: ExtraKeys {
    public func index() -> Int32 {
        return 0
    }
}

/// This implements the developer facing API for recording events.
///
/// Instances of this class type are automatically generated by the parsers at built time,
/// allowing developers to record events that were previously registered in the metrics.yaml file.
///
/// The Events API only exposes the `EventMetricType.record(extra:)` method, which takes care of validating the input
/// data and making sure that limits are enforced.
public class EventMetricType<ExtraKeysEnum: ExtraKeys> {
    let handle: UInt64
    let disabled: Bool
    let sendInPings: [String]

    /// The public constructor used by automatically generated metrics.
    public init(
        category: String,
        name: String,
        sendInPings: [String],
        lifetime: Lifetime,
        disabled: Bool,
        allowedExtraKeys: [String]? = nil
    ) {
        self.disabled = disabled
        self.sendInPings = sendInPings
        self.handle = withArrayOfCStrings(sendInPings) { pingArray in
            withArrayOfCStrings(allowedExtraKeys) { allowedExtraKeys in
                glean_new_event_metric(
                    category,
                    name,
                    pingArray,
                    Int32(sendInPings.count),
                    lifetime.rawValue,
                    disabled ? 1 : 0,
                    allowedExtraKeys,
                    Int32(allowedExtraKeys?.count ?? 0)
                )
            }
        }
    }

    /// Destroy this metric.
    deinit {
        if self.handle != 0 {
            glean_destroy_event_metric(self.handle)
        }
    }

    /// Record an event by using the information provided by the instance of this class.
    ///
    /// - parameters:
    ///     * extra: (optional) A map of extra keys. Keys are identiifers and mapped to their registered name,
    ///              values need to be strings.
    ///              This is used for events where additional richer context is needed.
    ///              The maximum length for values is defined by `MAX_LENGTH_EXTRA_KEY_VALUE`.
    public func record(extra: [ExtraKeysEnum: String]? = nil) {
        guard !self.disabled else { return }

        // We capture the event time now, since we don't know when the async code below
        // might get executed.
        let timestamp = timestampNanos()

        Dispatchers.shared.launchAPI {
            // The map is sent over FFI as a pair of arrays, one containing the
            // keys, and the other containing the values.
            var len = 0
            var keys: [Int32]?
            var values: [String]?

            if let extra = extra {
                len = extra.count

                if len > 0 {
                    keys = []
                    values = []
                    keys?.reserveCapacity(len)
                    values?.reserveCapacity(len)

                    for (key, value) in extra {
                        keys?.append(key.index())
                        values?.append(value)
                    }
                }
            }

            withArrayOfCStrings(values) { values in
                glean_event_record(
                    Glean.shared.handle,
                    self.handle,
                    timestamp,
                    keys,
                    values,
                    Int32(len)
                )
            }
        }
    }

    /// Tests whether a value is stored for the metric for testing purposes only. This function will
    /// attempt to await the last task (if any) writing to the the metric's storage engine before
    /// returning a value.
    ///
    /// - parameters:
    ///     * pingName: represents the name of the ping to retrieve the metric for.
    ///                 Defaults to the first value in `sendInPings`.
    /// - returns: true if metric value exists, otherwise false
    public func testHasValue(_ pingName: String? = nil) -> Bool {
        Dispatchers.shared.assertInTestingMode()

        let pingName = pingName ?? self.sendInPings[0]
        return glean_event_test_has_value(Glean.shared.handle, self.handle, pingName) != 0
    }

    /// Deserializes an event in JSON into a RecordedEventData object.
    ///
    /// - parameters:
    ///     * jsonContent: The JSONObject containing the data for the event. It is in
    ///       the same format as an event sent in a ping, and has the following entries:
    ///         - timestamp (Int)
    ///         - category (String): The category of the event metric
    ///         - name (String): The name of the event metric
    ///         - extra ([String: String]?): Map of extra key/value pairs
    /// - returns: `RecordedEventData` representing the event data
    private func deserializeEvent(_ jsonContent: [String: Any]) -> RecordedEventData? {
        guard let category = jsonContent["category"] as? String else { return nil }
        guard let name = jsonContent["name"] as? String else { return nil }
        guard let timestamp = jsonContent["timestamp"] as? UInt64 else { return nil }
        var extra: [String: String]?

        if let extraObj = jsonContent["extra"] {
            let extraObj = extraObj as? [String: String]
            extra = extraObj
        }

        return RecordedEventData(category: category, name: name, timestamp: timestamp, extra: extra)
    }

    /// Returns the stored value for testing purposes only. This function will attempt to await the
    /// last task (if any) writing to the the metric's storage engine before returning a value.
    ///
    /// Throws a "Missing value" exception if no value is stored
    ///
    /// - parameters:
    ///     * pingName: represents the name of the ping to retrieve the metric for.
    ///                 Defaults to the first value in `sendInPings`.
    ///
    /// - returns:  value of the stored metric
    public func testGetValue(_ pingName: String? = nil) throws -> [RecordedEventData] {
        Dispatchers.shared.assertInTestingMode()

        let pingName = pingName ?? self.sendInPings[0]

        if !testHasValue(pingName) {
            throw "Missing value"
        }

        let res = String(
            freeingRustString: glean_event_test_get_value_as_json_string(Glean.shared.handle, self.handle, pingName)
        )

        do {
            let data = res.data(using: .utf8)!
            // swiftlint:disable force_cast
            let jsonRes = try JSONSerialization.jsonObject(with: data, options: []) as! [Any]
            if jsonRes.isEmpty {
                throw "Missing value"
            }

            var result = [RecordedEventData]()
            for element in jsonRes {
                if let event = element as? [String: Any] {
                    if let event = deserializeEvent(event) {
                        result.append(event)
                    } else {
                        throw "Missing value"
                    }
                }
            }

            return result
        } catch {
            throw "Missing value"
        }
    }

    /// Returns the number of errors recorded for the given metric.
    ///
    /// - parameters:
    ///     * errorType: The type of error recorded.
    ///     * pingName: represents the name of the ping to retrieve the metric for.
    ///                 Defaults to the first value in `sendInPings`.
    ///
    /// - returns: The number of errors recorded for the metric for the given error type.
    public func testGetNumRecordedErrors(_ errorType: ErrorType, pingName: String? = nil) -> Int32 {
        Dispatchers.shared.assertInTestingMode()

        let pingName = pingName ?? self.sendInPings[0]

        return glean_event_test_get_num_recorded_errors(
            Glean.shared.handle,
            self.handle,
            errorType.rawValue,
            pingName
        )
    }
}
