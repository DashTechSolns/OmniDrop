// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pairing.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsPairingEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsPairingEvent()';
}


}

/// @nodoc
class $RsPairingEventCopyWith<$Res>  {
$RsPairingEventCopyWith(RsPairingEvent _, $Res Function(RsPairingEvent) __);
}


/// Adds pattern-matching-related methods to [RsPairingEvent].
extension RsPairingEventPatterns on RsPairingEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsPairingEvent_DeviceJoined value)?  deviceJoined,TResult Function( RsPairingEvent_Finalized value)?  finalized,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsPairingEvent_DeviceJoined() when deviceJoined != null:
return deviceJoined(_that);case RsPairingEvent_Finalized() when finalized != null:
return finalized(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsPairingEvent_DeviceJoined value)  deviceJoined,required TResult Function( RsPairingEvent_Finalized value)  finalized,}){
final _that = this;
switch (_that) {
case RsPairingEvent_DeviceJoined():
return deviceJoined(_that);case RsPairingEvent_Finalized():
return finalized(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsPairingEvent_DeviceJoined value)?  deviceJoined,TResult? Function( RsPairingEvent_Finalized value)?  finalized,}){
final _that = this;
switch (_that) {
case RsPairingEvent_DeviceJoined() when deviceJoined != null:
return deviceJoined(_that);case RsPairingEvent_Finalized() when finalized != null:
return finalized(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( JoinedPairingDevice device)?  deviceJoined,TResult Function()?  finalized,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsPairingEvent_DeviceJoined() when deviceJoined != null:
return deviceJoined(_that.device);case RsPairingEvent_Finalized() when finalized != null:
return finalized();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( JoinedPairingDevice device)  deviceJoined,required TResult Function()  finalized,}) {final _that = this;
switch (_that) {
case RsPairingEvent_DeviceJoined():
return deviceJoined(_that.device);case RsPairingEvent_Finalized():
return finalized();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( JoinedPairingDevice device)?  deviceJoined,TResult? Function()?  finalized,}) {final _that = this;
switch (_that) {
case RsPairingEvent_DeviceJoined() when deviceJoined != null:
return deviceJoined(_that.device);case RsPairingEvent_Finalized() when finalized != null:
return finalized();case _:
  return null;

}
}

}

/// @nodoc


class RsPairingEvent_DeviceJoined extends RsPairingEvent {
  const RsPairingEvent_DeviceJoined({required this.device}): super._();
  

 final  JoinedPairingDevice device;

/// Create a copy of RsPairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsPairingEvent_DeviceJoinedCopyWith<RsPairingEvent_DeviceJoined> get copyWith => _$RsPairingEvent_DeviceJoinedCopyWithImpl<RsPairingEvent_DeviceJoined>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingEvent_DeviceJoined&&(identical(other.device, device) || other.device == device));
}


@override
int get hashCode => Object.hash(runtimeType,device);

@override
String toString() {
  return 'RsPairingEvent.deviceJoined(device: $device)';
}


}

/// @nodoc
abstract mixin class $RsPairingEvent_DeviceJoinedCopyWith<$Res> implements $RsPairingEventCopyWith<$Res> {
  factory $RsPairingEvent_DeviceJoinedCopyWith(RsPairingEvent_DeviceJoined value, $Res Function(RsPairingEvent_DeviceJoined) _then) = _$RsPairingEvent_DeviceJoinedCopyWithImpl;
@useResult
$Res call({
 JoinedPairingDevice device
});




}
/// @nodoc
class _$RsPairingEvent_DeviceJoinedCopyWithImpl<$Res>
    implements $RsPairingEvent_DeviceJoinedCopyWith<$Res> {
  _$RsPairingEvent_DeviceJoinedCopyWithImpl(this._self, this._then);

  final RsPairingEvent_DeviceJoined _self;
  final $Res Function(RsPairingEvent_DeviceJoined) _then;

/// Create a copy of RsPairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? device = null,}) {
  return _then(RsPairingEvent_DeviceJoined(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as JoinedPairingDevice,
  ));
}


}

/// @nodoc


class RsPairingEvent_Finalized extends RsPairingEvent {
  const RsPairingEvent_Finalized(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingEvent_Finalized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsPairingEvent.finalized()';
}


}




/// @nodoc
mixin _$RsPairingTransferEvent {

 String get fingerprint; String get alias;
/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsPairingTransferEventCopyWith<RsPairingTransferEvent> get copyWith => _$RsPairingTransferEventCopyWithImpl<RsPairingTransferEvent>(this as RsPairingTransferEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingTransferEvent&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.alias, alias) || other.alias == alias));
}


@override
int get hashCode => Object.hash(runtimeType,fingerprint,alias);

@override
String toString() {
  return 'RsPairingTransferEvent(fingerprint: $fingerprint, alias: $alias)';
}


}

/// @nodoc
abstract mixin class $RsPairingTransferEventCopyWith<$Res>  {
  factory $RsPairingTransferEventCopyWith(RsPairingTransferEvent value, $Res Function(RsPairingTransferEvent) _then) = _$RsPairingTransferEventCopyWithImpl;
@useResult
$Res call({
 String fingerprint, String alias
});




}
/// @nodoc
class _$RsPairingTransferEventCopyWithImpl<$Res>
    implements $RsPairingTransferEventCopyWith<$Res> {
  _$RsPairingTransferEventCopyWithImpl(this._self, this._then);

  final RsPairingTransferEvent _self;
  final $Res Function(RsPairingTransferEvent) _then;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fingerprint = null,Object? alias = null,}) {
  return _then(_self.copyWith(
fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RsPairingTransferEvent].
extension RsPairingTransferEventPatterns on RsPairingTransferEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsPairingTransferEvent_DeviceStarted value)?  deviceStarted,TResult Function( RsPairingTransferEvent_DeviceFinished value)?  deviceFinished,TResult Function( RsPairingTransferEvent_DeviceFailed value)?  deviceFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsPairingTransferEvent_DeviceStarted() when deviceStarted != null:
return deviceStarted(_that);case RsPairingTransferEvent_DeviceFinished() when deviceFinished != null:
return deviceFinished(_that);case RsPairingTransferEvent_DeviceFailed() when deviceFailed != null:
return deviceFailed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsPairingTransferEvent_DeviceStarted value)  deviceStarted,required TResult Function( RsPairingTransferEvent_DeviceFinished value)  deviceFinished,required TResult Function( RsPairingTransferEvent_DeviceFailed value)  deviceFailed,}){
final _that = this;
switch (_that) {
case RsPairingTransferEvent_DeviceStarted():
return deviceStarted(_that);case RsPairingTransferEvent_DeviceFinished():
return deviceFinished(_that);case RsPairingTransferEvent_DeviceFailed():
return deviceFailed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsPairingTransferEvent_DeviceStarted value)?  deviceStarted,TResult? Function( RsPairingTransferEvent_DeviceFinished value)?  deviceFinished,TResult? Function( RsPairingTransferEvent_DeviceFailed value)?  deviceFailed,}){
final _that = this;
switch (_that) {
case RsPairingTransferEvent_DeviceStarted() when deviceStarted != null:
return deviceStarted(_that);case RsPairingTransferEvent_DeviceFinished() when deviceFinished != null:
return deviceFinished(_that);case RsPairingTransferEvent_DeviceFailed() when deviceFailed != null:
return deviceFailed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String fingerprint,  String alias)?  deviceStarted,TResult Function( String fingerprint,  String alias,  int filesSent)?  deviceFinished,TResult Function( String fingerprint,  String alias,  String error)?  deviceFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsPairingTransferEvent_DeviceStarted() when deviceStarted != null:
return deviceStarted(_that.fingerprint,_that.alias);case RsPairingTransferEvent_DeviceFinished() when deviceFinished != null:
return deviceFinished(_that.fingerprint,_that.alias,_that.filesSent);case RsPairingTransferEvent_DeviceFailed() when deviceFailed != null:
return deviceFailed(_that.fingerprint,_that.alias,_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String fingerprint,  String alias)  deviceStarted,required TResult Function( String fingerprint,  String alias,  int filesSent)  deviceFinished,required TResult Function( String fingerprint,  String alias,  String error)  deviceFailed,}) {final _that = this;
switch (_that) {
case RsPairingTransferEvent_DeviceStarted():
return deviceStarted(_that.fingerprint,_that.alias);case RsPairingTransferEvent_DeviceFinished():
return deviceFinished(_that.fingerprint,_that.alias,_that.filesSent);case RsPairingTransferEvent_DeviceFailed():
return deviceFailed(_that.fingerprint,_that.alias,_that.error);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String fingerprint,  String alias)?  deviceStarted,TResult? Function( String fingerprint,  String alias,  int filesSent)?  deviceFinished,TResult? Function( String fingerprint,  String alias,  String error)?  deviceFailed,}) {final _that = this;
switch (_that) {
case RsPairingTransferEvent_DeviceStarted() when deviceStarted != null:
return deviceStarted(_that.fingerprint,_that.alias);case RsPairingTransferEvent_DeviceFinished() when deviceFinished != null:
return deviceFinished(_that.fingerprint,_that.alias,_that.filesSent);case RsPairingTransferEvent_DeviceFailed() when deviceFailed != null:
return deviceFailed(_that.fingerprint,_that.alias,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RsPairingTransferEvent_DeviceStarted extends RsPairingTransferEvent {
  const RsPairingTransferEvent_DeviceStarted({required this.fingerprint, required this.alias}): super._();
  

@override final  String fingerprint;
@override final  String alias;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsPairingTransferEvent_DeviceStartedCopyWith<RsPairingTransferEvent_DeviceStarted> get copyWith => _$RsPairingTransferEvent_DeviceStartedCopyWithImpl<RsPairingTransferEvent_DeviceStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingTransferEvent_DeviceStarted&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.alias, alias) || other.alias == alias));
}


@override
int get hashCode => Object.hash(runtimeType,fingerprint,alias);

@override
String toString() {
  return 'RsPairingTransferEvent.deviceStarted(fingerprint: $fingerprint, alias: $alias)';
}


}

/// @nodoc
abstract mixin class $RsPairingTransferEvent_DeviceStartedCopyWith<$Res> implements $RsPairingTransferEventCopyWith<$Res> {
  factory $RsPairingTransferEvent_DeviceStartedCopyWith(RsPairingTransferEvent_DeviceStarted value, $Res Function(RsPairingTransferEvent_DeviceStarted) _then) = _$RsPairingTransferEvent_DeviceStartedCopyWithImpl;
@override @useResult
$Res call({
 String fingerprint, String alias
});




}
/// @nodoc
class _$RsPairingTransferEvent_DeviceStartedCopyWithImpl<$Res>
    implements $RsPairingTransferEvent_DeviceStartedCopyWith<$Res> {
  _$RsPairingTransferEvent_DeviceStartedCopyWithImpl(this._self, this._then);

  final RsPairingTransferEvent_DeviceStarted _self;
  final $Res Function(RsPairingTransferEvent_DeviceStarted) _then;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fingerprint = null,Object? alias = null,}) {
  return _then(RsPairingTransferEvent_DeviceStarted(
fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsPairingTransferEvent_DeviceFinished extends RsPairingTransferEvent {
  const RsPairingTransferEvent_DeviceFinished({required this.fingerprint, required this.alias, required this.filesSent}): super._();
  

@override final  String fingerprint;
@override final  String alias;
 final  int filesSent;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsPairingTransferEvent_DeviceFinishedCopyWith<RsPairingTransferEvent_DeviceFinished> get copyWith => _$RsPairingTransferEvent_DeviceFinishedCopyWithImpl<RsPairingTransferEvent_DeviceFinished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingTransferEvent_DeviceFinished&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.filesSent, filesSent) || other.filesSent == filesSent));
}


@override
int get hashCode => Object.hash(runtimeType,fingerprint,alias,filesSent);

@override
String toString() {
  return 'RsPairingTransferEvent.deviceFinished(fingerprint: $fingerprint, alias: $alias, filesSent: $filesSent)';
}


}

/// @nodoc
abstract mixin class $RsPairingTransferEvent_DeviceFinishedCopyWith<$Res> implements $RsPairingTransferEventCopyWith<$Res> {
  factory $RsPairingTransferEvent_DeviceFinishedCopyWith(RsPairingTransferEvent_DeviceFinished value, $Res Function(RsPairingTransferEvent_DeviceFinished) _then) = _$RsPairingTransferEvent_DeviceFinishedCopyWithImpl;
@override @useResult
$Res call({
 String fingerprint, String alias, int filesSent
});




}
/// @nodoc
class _$RsPairingTransferEvent_DeviceFinishedCopyWithImpl<$Res>
    implements $RsPairingTransferEvent_DeviceFinishedCopyWith<$Res> {
  _$RsPairingTransferEvent_DeviceFinishedCopyWithImpl(this._self, this._then);

  final RsPairingTransferEvent_DeviceFinished _self;
  final $Res Function(RsPairingTransferEvent_DeviceFinished) _then;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fingerprint = null,Object? alias = null,Object? filesSent = null,}) {
  return _then(RsPairingTransferEvent_DeviceFinished(
fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,filesSent: null == filesSent ? _self.filesSent : filesSent // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RsPairingTransferEvent_DeviceFailed extends RsPairingTransferEvent {
  const RsPairingTransferEvent_DeviceFailed({required this.fingerprint, required this.alias, required this.error}): super._();
  

@override final  String fingerprint;
@override final  String alias;
 final  String error;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsPairingTransferEvent_DeviceFailedCopyWith<RsPairingTransferEvent_DeviceFailed> get copyWith => _$RsPairingTransferEvent_DeviceFailedCopyWithImpl<RsPairingTransferEvent_DeviceFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsPairingTransferEvent_DeviceFailed&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,fingerprint,alias,error);

@override
String toString() {
  return 'RsPairingTransferEvent.deviceFailed(fingerprint: $fingerprint, alias: $alias, error: $error)';
}


}

/// @nodoc
abstract mixin class $RsPairingTransferEvent_DeviceFailedCopyWith<$Res> implements $RsPairingTransferEventCopyWith<$Res> {
  factory $RsPairingTransferEvent_DeviceFailedCopyWith(RsPairingTransferEvent_DeviceFailed value, $Res Function(RsPairingTransferEvent_DeviceFailed) _then) = _$RsPairingTransferEvent_DeviceFailedCopyWithImpl;
@override @useResult
$Res call({
 String fingerprint, String alias, String error
});




}
/// @nodoc
class _$RsPairingTransferEvent_DeviceFailedCopyWithImpl<$Res>
    implements $RsPairingTransferEvent_DeviceFailedCopyWith<$Res> {
  _$RsPairingTransferEvent_DeviceFailedCopyWithImpl(this._self, this._then);

  final RsPairingTransferEvent_DeviceFailed _self;
  final $Res Function(RsPairingTransferEvent_DeviceFailed) _then;

/// Create a copy of RsPairingTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fingerprint = null,Object? alias = null,Object? error = null,}) {
  return _then(RsPairingTransferEvent_DeviceFailed(
fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
