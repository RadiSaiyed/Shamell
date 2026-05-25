import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_page.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';

void main() {
  group('ride booking validation', () {
    const pickup = RideSearchPlace(
      displayName: 'Bab Touma Damascus',
      point: RideGeoPoint(lat: 33.5138, lon: 36.3138),
    );
    const destination = RideSearchPlace(
      displayName: 'Malki Damascus',
      point: RideGeoPoint(lat: 33.5152, lon: 36.29637),
    );

    test('matches normalized selected place labels', () {
      expect(
        ridePlaceSelectionMatchesQuery(
          query: '  Bab   Touma   Damascus ',
          selectedPlace: pickup,
        ),
        isTrue,
      );
      expect(
        ridePlaceSelectionMatchesQuery(
          query: 'Malki',
          selectedPlace: pickup,
        ),
        isFalse,
      );
    });

    test('requires resolved pickup and destination selections', () {
      expect(
        rideBookingValidationIssue(
          pickupQuery: 'Bab Touma Damascus',
          destinationQuery: 'Malki Damascus',
          selectedPickup: null,
          selectedDestination: destination,
          hasActiveTrip: false,
        ),
        RideBookingValidationIssue.pickupUnresolved,
      );
      expect(
        rideBookingValidationIssue(
          pickupQuery: 'Bab Touma Damascus',
          destinationQuery: 'Malki Damascus',
          selectedPickup: pickup,
          selectedDestination: null,
          hasActiveTrip: false,
        ),
        RideBookingValidationIssue.destinationUnresolved,
      );
    });

    test('rejects pickup and destination that resolve to same point', () {
      const sameDestination = RideSearchPlace(
        displayName: 'Damascus Gate',
        point: RideGeoPoint(lat: 33.51381, lon: 36.31379),
      );
      expect(
        rideBookingValidationIssue(
          pickupQuery: pickup.displayName,
          destinationQuery: sameDestination.displayName,
          selectedPickup: pickup,
          selectedDestination: sameDestination,
          hasActiveTrip: false,
        ),
        RideBookingValidationIssue.samePlace,
      );
    });

    test('allows submit only when both sides are resolved and distinct', () {
      expect(
        rideBookingValidationIssue(
          pickupQuery: pickup.displayName,
          destinationQuery: destination.displayName,
          selectedPickup: pickup,
          selectedDestination: destination,
          hasActiveTrip: false,
        ),
        isNull,
      );
    });

    test('distinguishes no-results from unavailable autocomplete states', () {
      expect(
        ridePlaceSuggestionFeedback(
          query: 'Malki',
          loading: false,
          unavailable: false,
          suggestions: const <RideSearchPlace>[],
        ),
        RidePlaceSuggestionFeedback.noResults,
      );
      expect(
        ridePlaceSuggestionFeedback(
          query: 'Malki',
          loading: false,
          unavailable: true,
          suggestions: const <RideSearchPlace>[],
        ),
        RidePlaceSuggestionFeedback.unavailable,
      );
      expect(
        ridePlaceSuggestionFeedback(
          query: 'M',
          loading: false,
          unavailable: true,
          suggestions: const <RideSearchPlace>[],
        ),
        RidePlaceSuggestionFeedback.none,
      );
    });
  });
}
