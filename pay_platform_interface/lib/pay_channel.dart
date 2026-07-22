// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'core/payment_configuration.dart';
import 'core/payment_item.dart';
import 'pay_platform_interface.dart';

/// An implementation of the contract in this plugin that uses a [MethodChannel]
/// and an [EventChannel] to communicate with the native end.
///
/// Example of a simple method channel:
///
/// ```dart
/// PayPlatform platform = PayMethodChannel();
/// final canPay = await platform.userCanPay(configuration);
/// final paymentData = await platform.showPaymentSelector(
///     configuration, paymentItems);
/// ```
class PayMethodChannel extends PayPlatform {
  // The channel used to send messages down the native pipe.
  final MethodChannel _channel = const MethodChannel('plugins.flutter.io/pay');
  static const EventChannel _eventChannel = EventChannel('plugins.flutter.io/pay_events');

  // Stream for payment events
  final StreamController<Map<String, dynamic>> _eventStreamController = StreamController.broadcast();

  PayMethodChannel() {
    // The `pay_events` EventChannel is only implemented on the Android side of
    // the plugin (pay_android). iOS registers no handler for it, so subscribing
    // on iOS throws MissingPluginException on every PayMethodChannel creation
    // (CRDES-45750). Only Android delivers the payment result over this stream;
    // iOS reads it directly from showPaymentSelector, so skipping the
    // subscription there is a no-op behaviourally.
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Listen to the event channel and add events to the stream controller
      _eventChannel.receiveBroadcastStream().listen((dynamic event) {
        final Map<String, dynamic> eventData = jsonDecode(event as String) as Map<String, dynamic>;
        _eventStreamController.add(eventData);
      }, onError: (dynamic error) {
        // Flush error to the event stream controller
        _eventStreamController.addError('[PayMethodChannel] Error receiving event: $error');
      });
    }
  }

  /// Provides a stream of payment events.
  @override
  Stream<Map<String, dynamic>> get events => _eventStreamController.stream;

  /// Determines whether a user can pay with the provider in the configuration.
  ///
  /// Completes with a [PlatformException] if the native call fails or otherwise
  /// returns a boolean for the [paymentConfiguration] specified.
  @override
  Future<bool> userCanPay(PaymentConfiguration paymentConfiguration) async {
    return await _channel.invokeMethod('userCanPay', jsonEncode(await paymentConfiguration.parameterMap())) as bool;
  }

  /// Shows the payment selector to complete the payment operation.
  ///
  /// Shows the payment selector with the [paymentItems] and
  /// [paymentConfiguration] specified, returning the payment method selected as
  /// a result if the operation completes successfully, or throws a
  /// [PlatformException] if there's an error on the native end.
  @override
  Future<Map<String, dynamic>> showPaymentSelector(
    PaymentConfiguration paymentConfiguration,
    List<PaymentItem> paymentItems,
  ) async {
    final paymentResult = await _channel.invokeMethod('showPaymentSelector', {
      'payment_profile': jsonEncode(await paymentConfiguration.parameterMap()),
      'payment_items': paymentItems.map((item) => item.toMap()).toList(),
    }) as String?;

    return jsonDecode(paymentResult ?? '{}') as Map<String, dynamic>;
  }

  /// Close the event stream controller when done.
  void dispose() {
    _eventStreamController.close();
  }
}
