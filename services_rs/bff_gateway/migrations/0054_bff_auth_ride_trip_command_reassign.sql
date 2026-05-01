ALTER TABLE auth_ride_trip_commands
    DROP CONSTRAINT IF EXISTS chk_auth_ride_trip_commands_command_known;

ALTER TABLE auth_ride_trip_commands
    ADD CONSTRAINT chk_auth_ride_trip_commands_command_known
        CHECK (
            command IN (
                'request_ride',
                'enter_matching',
                'assign_driver',
                'mark_driver_arriving',
                'mark_driver_arrived',
                'start_trip',
                'mark_in_progress',
                'mark_payment_failed',
                'complete_trip',
                'cancel_trip',
                'reassign_trip'
            )
        );
