// Copyright 2024 Yandex LLC. All rights reserved.

#ifndef BASE_IOS_YANDEX_IMPLICITS_RUNTIME_PERFORMANCE_MEASURING_H_
#define BASE_IOS_YANDEX_IMPLICITS_RUNTIME_PERFORMANCE_MEASURING_H_

#include <CoreFoundation/CoreFoundation.h>

/*
 List of things to measure:
 */
#define SUBJECT_ENUMERATION(SUBJECT)   \
  SUBJECT(Control)                     \
  SUBJECT(ImplicitsWithUnsafeKeys)     \
  SUBJECT(RawStoreOnRootScopeCreation) \
  SUBJECT(RawStoreOnRootScopeEnd)      \
  SUBJECT(RawStoreSubscriptSet)        \
  SUBJECT(RawStoreSubscriptGet)        \
  SUBJECT(RawStoreCurrent)             \
  SUBJECT(RawStoreFromTSD)             \
  SUBJECT(TypedStoreSubscriptGet)      \
  SUBJECT(TypedStoreSetValue)

/*
 Declare functions to record and read measurements for each subject.
 */
#define RECORD_AND_READ_MEASUREMENT_FUNCTIONS(SUBJECT) \
  void RecordMeasurementFor##SUBJECT(uint64_t ns);     \
  uint64_t GetAccumulatedMetricFor##SUBJECT(void);     \
  uint64_t GetCounterFor##SUBJECT(void);

SUBJECT_ENUMERATION(RECORD_AND_READ_MEASUREMENT_FUNCTIONS)

/*
 Enum to identify the subject of the measurement.
 */
#define ENUM_MEMBER(s) InternalImplicitsMeasurementSubject##s,
typedef CF_CLOSED_ENUM(uint64_t, InternalImplicitsMeasurementSubject) {
  SUBJECT_ENUMERATION(ENUM_MEMBER)
};

/*
 Generic function to record a measurement for a subject.
 */
#define CASE_RECORD_MEASUREMENT(SUBJECT)             \
  case InternalImplicitsMeasurementSubject##SUBJECT: \
    RecordMeasurementFor##SUBJECT(ns);               \
    break;

inline static void RecordMeasurement(
    InternalImplicitsMeasurementSubject subject,
    uint64_t ns) {
  switch (subject) {
    SUBJECT_ENUMERATION(CASE_RECORD_MEASUREMENT)
    default:
      break;
  }
}

/*
 Generic function to get accumulated metric for a subject.
 */
#define CASE_GET_ACCUMULATED_METRIC(SUBJECT)         \
  case InternalImplicitsMeasurementSubject##SUBJECT: \
    return GetAccumulatedMetricFor##SUBJECT();

inline static uint64_t GetAccumulatedMetricFor(
    InternalImplicitsMeasurementSubject subject) {
  switch (subject) {
    SUBJECT_ENUMERATION(CASE_GET_ACCUMULATED_METRIC)
    default:
      return 0;
  }
}

/*
 Generic function to get counter for a subject.
 */
#define CASE_GET_COUNTER(SUBJECT)                    \
  case InternalImplicitsMeasurementSubject##SUBJECT: \
    return GetCounterFor##SUBJECT();

inline static uint64_t GetCounterFor(
    InternalImplicitsMeasurementSubject subject) {
  switch (subject) {
    SUBJECT_ENUMERATION(CASE_GET_COUNTER)
    default:
      return 0;
  }
}

#endif  // BASE_IOS_YANDEX_IMPLICITS_RUNTIME_PERFORMANCE_MEASURING_H_
