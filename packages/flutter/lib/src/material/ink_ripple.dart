// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'ink_well.dart';
import 'material.dart';

const Duration _kRadiusDuration = Duration(milliseconds: 225);
const Duration _kFadeOutDuration = Duration(milliseconds: 150);

const Curve _kRadiusCurve = Curves.fastOutSlowIn;
const Curve _kFadeOutCurve = Curves.linear;

RectCallback? _getClipCallback(RenderBox referenceBox, bool containedInkWell, RectCallback? rectCallback) {
  if (containedInkWell)
    return rectCallback ?? () => Offset.zero & referenceBox.size;
  return null;
}

Size _getBounds(RenderBox referenceBox, RectCallback? rectCallback, Offset position) {
  return rectCallback != null ? rectCallback().size : referenceBox.size;
}

double _getInitialRadius(Size bounds) {
  return math.max(bounds.width, bounds.height) * 0.3;
}

double _getTargetRadius(Size bounds) {
  return bounds.center(Offset.zero).distance;
}

Offset _getInitialPosition(Offset position, Size bounds, double initialRadius, double targetRadius) {
  final Offset center = bounds.center(Offset.zero);
  final Offset positionFromCenter = position - center;
  final double dR = targetRadius - initialRadius;
  if (positionFromCenter.distanceSquared > dR * dR) {
    final double angle = math.atan2(positionFromCenter.dy, positionFromCenter.dx);
    final double initialPositionX = center.dx + dR * math.cos(angle);
    final double initialPositionY = center.dy + dR * math.sin(angle);
    return Offset(initialPositionX, initialPositionY);
  }
  return position;
}

class _InkRippleFactory extends InteractiveInkFeatureFactory {
  const _InkRippleFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return InkRipple(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
      textDirection: textDirection,
    );
  }
}

/// A visual reaction on a piece of [Material] to user input. Implemented to be
/// visually identical to the Android material ripple animation on AOSP API
/// versions 28 and above.
///
/// A circular ink feature whose origin starts at the input touch point and
/// whose radius expands from 60% of the final radius. The splash origin
/// animates to the center of its [referenceBox].
///
/// This object is rarely created directly. Instead of creating an ink ripple,
/// consider using an [InkResponse] or [InkWell] widget, which uses
/// gestures (such as tap and long-press) to trigger ink splashes. This class
/// is used when the [Theme]'s [ThemeData.splashFactory] is [InkRipple.splashFactory].
///
/// See also:
///
///  * [InkSplash], which is an ink splash feature that expands less
///    aggressively than the ripple.
///  * [InkRipplet], which is visually similar to the [InkRipple], but has a
///    background highlight, and a smaller initial radius.
///  * [InkResponse], which uses gestures to trigger ink highlights and ink
///    splashes in the parent [Material].
///  * [InkWell], which is a rectangular [InkResponse] (the most common type of
///    ink response).
///  * [Material], which is the widget on which the ink splash is painted.
///  * [InkHighlight], which is an ink feature that emphasizes a part of a
///    [Material].
class InkRipple extends InteractiveInkFeature {
  /// Begin a ripple, centered at [position] relative to [referenceBox].
  ///
  /// The [controller] argument is typically obtained via
  /// `Material.of(context)`.
  ///
  /// If [containedInkWell] is true, then the ripple will be sized to fit
  /// the well rectangle, then clipped to it when drawn. The well
  /// rectangle is the box returned by [rectCallback], if provided, or
  /// otherwise is the bounds of the [referenceBox].
  ///
  /// If [containedInkWell] is false, then [rectCallback] should be null.
  /// The ink ripple is clipped only to the edges of the [Material].
  /// This is the default.
  ///
  /// When the ripple is removed, [onRemoved] will be called.
  InkRipple({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) : _bounds = _getBounds(referenceBox, rectCallback, position),
       _borderRadius = borderRadius ?? BorderRadius.zero,
       _customBorder = customBorder,
       _textDirection = textDirection,
       _clipCallback = _getClipCallback(referenceBox, containedInkWell, rectCallback),
       super(controller: controller, referenceBox: referenceBox, color: color, onRemoved: onRemoved) {

    _targetRadius = radius ?? _getTargetRadius(_bounds);
    _initialRadius = _getInitialRadius(_bounds);
    _position = _getInitialPosition(position, _bounds, _initialRadius, _targetRadius);

    // Controls the splash radius and its center. Starts immediately.
    _radiusController = AnimationController(duration: _kRadiusDuration, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_handleRadiusStatusChanged)
      ..forward();
    _radius = _radiusController.drive(
      Tween<double>(
        begin: _initialRadius,
        end: _targetRadius,
      ).chain(CurveTween(curve: _kRadiusCurve)),
    );

    // Controls the ripple's alpha fade out animation. Starts on cancel,
    // or after the tap is confirmed and the radius animation finishes.
    _fadeOutController = AnimationController(duration: _kFadeOutDuration, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_handleAlphaStatusChanged);
    _fadeOut = _fadeOutController.drive(
      IntTween(
        begin: color.alpha,
        end: 0,
      ).chain(CurveTween(curve: _kFadeOutCurve)),
    );

    controller.addInkFeature(this);
  }

  final Size _bounds;
  final BorderRadius _borderRadius;
  final ShapeBorder? _customBorder;
  final RectCallback? _clipCallback;
  final TextDirection _textDirection;

  late Offset _position;

  late double _initialRadius;
  late double _targetRadius;

  late Animation<double> _radius;
  late AnimationController _radiusController;

  late Animation<int> _fadeOut;
  late AnimationController _fadeOutController;

  bool _confirmed = false;

  /// Used to specify that an [InkWell] or [InkResponse] should create an [InkRipple]
  /// for tap animations. This can be set by default by setting [InkRipple.splashFactory]
  /// as the [Theme.splashFactory] on a material [Theme].
  static const InteractiveInkFeatureFactory splashFactory = _InkRippleFactory();

  void _startFadeOut() {
    _fadeOutController.animateTo(1.0, duration: _kFadeOutDuration);
  }

  @override
  void confirm() {
    if (_radiusController.isAnimating) {
      _radiusController
        ..duration = _kRadiusDuration
        ..forward();
    } else {
      _startFadeOut();
    }

    _confirmed = true;
  }

  @override
  void cancel() {
    _startFadeOut();
  }

  void _handleAlphaStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed)
      dispose();
  }

  void _handleRadiusStatusChanged(AnimationStatus status) {
    // If the tap is not confirmed, then the ripple is for a long press, and the
    // ripple should not fade out yet. It will eventually fade out on confirm or cancel.
    if (status == AnimationStatus.completed && _confirmed)
      _startFadeOut();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final Paint paint = Paint()..color = color.withAlpha(_fadeOut.value);
    // Splash moves to the center of the reference box.
    final Offset center = Offset.lerp(
      _position,
      referenceBox.size.center(Offset.zero),
      _kRadiusCurve.transform(_radiusController.value),
    )!;
    paintInkCircle(
      canvas: canvas,
      transform: transform,
      paint: paint,
      center: center,
      textDirection: _textDirection,
      radius: _radius.value,
      customBorder: _customBorder,
      borderRadius: _borderRadius,
      clipCallback: _clipCallback,
    );
  }
}
