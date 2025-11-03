// lib/core/models/enums.dart

// This enum defines the day of the week, used by both recurring
// gigs and venue jam sessions.
enum DayOfWeek { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

// This enum defines the frequency of a recurring event, used by both
// recurring gigs and venue jam sessions.
enum JamFrequencyType {
  weekly,
  biWeekly, // Every 2 weeks
  monthlySameDay, // e.g., the 2nd Friday of every month
  monthlySameDate, // e.g., the 15th of every month
  customNthDay, // e.g., every 3rd Friday
}
