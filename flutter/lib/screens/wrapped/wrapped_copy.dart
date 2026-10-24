// Every line of text on the Wrapped cards, so wording can change without
// touching layout. Headlines are written in caps here; the cards don't
// uppercase them again.

import '../../models/wrapped.dart';
import 'wrapped_card.dart';

// --- Card 1: total hours -----------------------------------------------------

const kTotalHoursEyebrow = 'TIME PLAYED';

/// "214.5 HOURS", "1 HOUR". [shown] is the number while it counts up; the
/// decimals and unit follow the final [hours].
String totalHoursHeadline(double shown, double hours) =>
    '${formatNumber(shown, decimals: hoursDecimals(hours))} ${hoursUnit(hours).toUpperCase()}';

String totalHoursLine(double hours, int year) =>
    hours >= 48 ? "That's ${(hours / 24).floor()} full days of gaming in $year." : 'Every hour you logged in $year.';

// --- Card 2: games played ----------------------------------------------------

const kGamesPlayedEyebrow = 'GAMES PLAYED';

/// The word after the count in "18 GAMES".
String gamesPlayedUnit(int count) => count == 1 ? 'GAME' : 'GAMES';

String gamesPlayedLine(int count) => switch (count) {
  0 => 'Your next world is waiting.',
  1 => 'One world, fully explored.',
  _ => '$count different worlds explored this year.',
};

// --- Cards 3 and 5: featured game --------------------------------------------

const kTopGameEyebrow = 'YOUR #1 GAME';
const kTopOnlineGameEyebrow = 'YOUR TOP ONLINE GAME';
const kHoursPlayedLabel = 'HOURS PLAYED';
const kShareOfYearLabel = 'OF YOUR YEAR';

/// "45%" of the year's hours, or null when there's no total to compare with.
String? shareOfYear(double hours, double? totalHours) =>
    totalHours == null || totalHours <= 0 ? null : '${(hours / totalHours * 100).round()}%';

// --- Card 4: top games -------------------------------------------------------

const kTopGamesEyebrow = 'YOUR TOP GAMES';

String topGamesHeadline(int count) => 'TOP $count';

// --- Card 6: trophies --------------------------------------------------------

const kTrophiesEyebrow = 'TROPHIES';

/// "14 EARNED", "1 EARNED". [count] is the number shown while counting up.
String trophiesHeadline(int count) => '${formatNumber(count.toDouble())} EARNED';

/// "Elden Ring · 2 May", or just the part that is known.
String trophySubtitle(WrappedTrophy trophy) =>
    [?trophy.gameName, if (trophy.unlockedAt case final date?) formatDayMonth(date.toLocal())].join(' · ');

// --- Card 7: player type -----------------------------------------------------

const kPlayerTypeEyebrow = 'THIS YEAR YOU WERE';

String playerTypeName(PlayerType type) => switch (type) {
  PlayerType.creditsChaser => 'CREDITS CHASER',
  PlayerType.foreverInProgress => 'FOREVER IN PROGRESS',
  PlayerType.theCloser => 'THE CLOSER',
  PlayerType.theJuggler => 'THE JUGGLER',
  PlayerType.saveAndQuit => 'SAVE & QUIT',
};

/// What the type means, in words. No counts: Card 8 shows those next.
String playerTypeReason(PlayerType type) => switch (type) {
  PlayerType.creditsChaser => 'Once you start a game, you see it all the way to the credits.',
  PlayerType.foreverInProgress => "No rush to reach the ending. For you, it's all about the journey.",
  PlayerType.theCloser => 'You like to finish what you start. Your stories reach their ending.',
  PlayerType.theJuggler => "Why stick to one? You'd rather juggle a few games at once.",
  PlayerType.saveAndQuit => "You play at your own pace, pausing and coming back when you're ready.",
};

// --- Card 8: game status -----------------------------------------------------

const kGameStatusEyebrow = 'HOW YOUR GAMES LANDED';

String gameStatusHeadline(int total) => total == 1 ? '1 GAME' : '${formatNumber(total.toDouble())} GAMES';

const kStatusCompleted = 'Completed';
const kStatusPlaying = 'Still playing';
const kStatusPaused = 'Paused';

// --- Card 9: rating ----------------------------------------------------------

const kRatingEyebrow = 'YOUR RATINGS';

String ratingHeadline(WrappedRating rating) => switch (rating.raterType) {
  RaterType.toughCritic => 'TOUGH CRITIC',
  RaterType.fairJudge => 'FAIR JUDGE',
  RaterType.generousCritic => 'GENEROUS CRITIC',
  null => 'YOUR RATINGS',
};

/// With no rater type the headline already says "YOUR RATINGS".
String ratingEyebrow(WrappedRating rating) => rating.raterType == null
    ? '${rating.ratedGames} ${rating.ratedGames == 1 ? 'GAME' : 'GAMES'} RATED'
    : kRatingEyebrow;

/// The comparison with other players, or null when there's nothing to say.
String? ratingLine(WrappedRating rating) {
  final gap = rating.averageGap?.abs().toStringAsFixed(1);
  return switch (rating.raterType) {
    RaterType.toughCritic when gap != null => 'You rate games $gap★ lower than other players, on average.',
    RaterType.generousCritic when gap != null => 'You rate games $gap★ higher than other players, on average.',
    RaterType.fairJudge => 'Your scores land within half a star of other players.',
    _ => null,
  };
}

String ratingAverageCaption(int ratedGames) => 'average across $ratedGames ${ratedGames == 1 ? 'game' : 'games'}';

// --- Card 10: friends' hours -------------------------------------------------

const kFriendsHoursEyebrow = 'YOU VS YOUR FRIENDS';
const kYourRankLabel = 'YOUR RANK';
const kFriendsBeatenLabel = 'FRIENDS BEATEN';

enum HoursOutcome { win, loss, tie }

HoursOutcome hoursOutcome(double mine, double rivals) =>
    mine > rivals ? HoursOutcome.win : (mine < rivals ? HoursOutcome.loss : HoursOutcome.tie);

String displayName(WrappedUser user) => user.username ?? 'Your friend';

String friendsHoursHeadline(HoursOutcome outcome, WrappedUser rival) => switch (outcome) {
  HoursOutcome.win => 'YOU WIN',
  HoursOutcome.loss => '${displayName(rival).toUpperCase()} WINS',
  HoursOutcome.tie => 'DEAD HEAT',
};

String friendsHoursLine(HoursOutcome outcome, WrappedUser rival, double mine, double rivals) {
  final name = displayName(rival);
  final diff = formatHours((mine - rivals).abs());
  return switch (outcome) {
    HoursOutcome.win => 'You out-played $name by $diff.',
    HoursOutcome.loss => '$name out-played you by $diff.',
    HoursOutcome.tie => 'You and $name both played ${formatHours(mine)}.',
  };
}

String yourRankValue(WrappedFriendsHours stats) => '#${stats.userRank} of ${stats.friendsCounted + 1}';

// --- Card 11: most similar friend --------------------------------------------

const kGamingTwinEyebrow = 'YOUR GAMING TWIN';
const kMatchLabel = 'MATCH';
const kBothLoveLabel = 'YOU BOTH LOVE';

String sharedGenresValue(List<String> genres) => genres.join(' · ');

// --- Semantics ---------------------------------------------------------------

String trophiesSemantics(int count) => '$count ${count == 1 ? 'trophy' : 'trophies'} earned this year';

String gameStatusSemantics(WrappedPlayStyle style) =>
    'Of ${style.total} games: ${style.finished} completed, ${style.playing} still playing, ${style.paused} paused';

String ratingSemantics(WrappedRating rating) =>
    'Average rating ${rating.averageStars.toStringAsFixed(1)} out of 5 stars across ${rating.ratedGames} games. '
    '${[for (var n = 5; n >= 1; n--) '$n stars: ${rating.starCounts[n - 1]}'].join(', ')}';

String friendsHoursSemantics(WrappedUser rival, double mine, double rivals) =>
    'You played ${formatHours(mine)}. ${displayName(rival)} played ${formatHours(rivals)}.';

String similarFriendSemantics(WrappedSimilarFriend friend) =>
    'You and ${displayName(friend.user)} are a ${friend.matchPercent} percent match';
