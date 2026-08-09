import 'dart:math';

import '../../models/challenge_model.dart';

/// A single parameterizable seed passed to [ChallengeGenerationService].
///
/// Seeds are NOT pre-written challenges — they are structured ingredients
/// that Gemini combines with time, weather, and day context to generate
/// a unique, fully-described challenge.
class ChallengeSeed {
  const ChallengeSeed({
    required this.category,
    required this.theme,
    required this.difficulty,
    required this.action,
    required this.subject,
    required this.successHint,
  });

  final ChallengeCategory category;

  /// Short descriptive phrase, e.g. "insects and small creatures".
  final String theme;
  final ChallengeDifficulty difficulty;

  /// Verb phrase for the objective, e.g. "photograph".
  final String action;

  /// What the user focuses on, e.g. "an insect in its natural habitat".
  final String subject;

  /// What a verifying photo should show, e.g. "a close-up of an insect outdoors".
  final String successHint;

  /// Produces a seed identifier string stored in the challenge document.
  @override
  String toString() => '${category.name}|$theme|${difficulty.name}';
}

/// Provides parameterizable challenge seeds across 8 categories — see
/// [ChallengeSeedLibrary.count] for the current total.
///
/// Each seed is not a pre-written challenge; Gemini combines it with time,
/// weather, and day context to generate fresh title/description text, so
/// the same seed never produces byte-identical challenges. Even so, the
/// underlying objective repeats once a user's streak exceeds [count] days —
/// grow this library over time rather than treating the count as fixed.
///
/// Seeds are selected deterministically by day number + user hash so:
/// - The same user gets consistent variety over time
/// - Different users on the same day get different challenges
/// - Days are uniquely seeded across [count] rotations before repeating
abstract final class ChallengeSeedLibrary {
  static final _random = Random();

  static const _allSeeds = [
    // Nature — easy (action: photograph, subject varies per theme)
    ..._natureSeeds,
    // Observation — mixed
    ..._observationSeeds,
    // Exercise — mixed
    ..._exerciseSeeds,
    // Exploration — mixed
    ..._explorationSeeds,
    // Photography — mixed
    ..._photographySeeds,
    // Mindfulness — mixed
    ..._mindfulnessSeeds,
    // Environmental — mixed
    ..._environmentalSeeds,
    // Micro Adventures — mixed
    ..._microAdventureSeeds,
  ];

  static const List<ChallengeSeed> _natureSeeds = [
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'insects and small creatures', difficulty: ChallengeDifficulty.medium, action: 'photograph', subject: 'an insect or tiny creature in its natural habitat', successHint: 'a close-up photo of an insect or small creature outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'wildflowers in bloom', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a wildflower growing naturally outside', successHint: 'a wildflower clearly visible in an outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'tree bark and texture', difficulty: ChallengeDifficulty.easy, action: 'photograph', subject: 'the texture of tree bark up close', successHint: 'a close-up detail of tree bark outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'mosses and lichens', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'moss or lichen on a surface outdoors', successHint: 'moss or lichen clearly visible on a rock, wall, or tree'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'roots and soil', difficulty: ChallengeDifficulty.easy, action: 'photograph', subject: 'exposed roots or interesting soil formation', successHint: 'visible tree roots or soil structure outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'bird life', difficulty: ChallengeDifficulty.hard, action: 'spot and photograph', subject: 'a wild bird in its natural environment', successHint: 'a bird clearly visible outdoors in a natural setting'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'spider webs', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'a spider web catching light or dew', successHint: 'a spider web visible outdoors with structure showing'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'fungi and mushrooms', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'a fungus or mushroom growing naturally', successHint: 'a fungus or mushroom in a natural outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'seeds and seedpods', difficulty: ChallengeDifficulty.easy, action: 'collect and photograph', subject: 'seeds or seed pods from different plants', successHint: 'seeds or seedpods clearly visible, ideally multiple types'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'leaves and veins', difficulty: ChallengeDifficulty.easy, action: 'photograph', subject: 'leaf vein patterns held against the light', successHint: 'a leaf with visible vein structure, ideally backlit'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'pollinators at work', difficulty: ChallengeDifficulty.hard, action: 'observe and photograph', subject: 'a bee, butterfly, or other pollinator on a flower', successHint: 'a pollinator clearly on or near a flower outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'plant buds and new growth', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a new bud, sprout, or emerging growth', successHint: 'young plant growth or a bud clearly visible outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'symmetry in plants', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'natural symmetry in a plant, flower, or leaf', successHint: 'a plant or leaf showing clear natural symmetry'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'seasonal change', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'something that shows the current season in nature', successHint: 'an outdoor scene clearly showing the current season'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'dead wood and decay', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a fallen log or decaying wood with life on it', successHint: 'decaying wood with moss, fungi, or small creatures visible'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'camouflage in nature', difficulty: ChallengeDifficulty.hard, action: 'spot and photograph', subject: 'an animal, insect, or plant using camouflage outdoors', successHint: 'something camouflaged in its natural outdoor environment'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'fruit and berries', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'wild fruit or berries growing naturally outdoors', successHint: 'fruit or berries on a plant in a natural outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'animal tracks or signs', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'animal tracks, a burrow, or other wildlife sign outdoors', successHint: 'animal tracks, a burrow entrance, or clear wildlife sign outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'reptiles and amphibians', difficulty: ChallengeDifficulty.hard, action: 'spot and photograph', subject: 'a lizard, frog, snake, or other reptile/amphibian in the wild', successHint: 'a reptile or amphibian clearly visible outdoors in its habitat'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'thorns and plant defenses', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'thorns, spines, or another natural plant defense mechanism', successHint: 'thorns or spines clearly visible on a plant outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'aquatic and wetland plants', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a plant growing in or right at the edge of water', successHint: 'a plant growing in water or at a waterline, clearly visible outdoors'),
    ChallengeSeed(category: ChallengeCategory.nature, theme: 'unusual leaf shapes', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a leaf with an unusually shaped or distinctive outline', successHint: 'a single leaf with a clearly distinctive shape, photographed outdoors'),
  ];

  static const List<ChallengeSeed> _observationSeeds = [
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'cloud formations', difficulty: ChallengeDifficulty.easy, action: 'observe and photograph', subject: 'an interesting cloud formation in the sky', successHint: 'an interesting cloud shape clearly visible in the sky'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'shadows and light', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'an interesting or unexpected shadow cast outdoors', successHint: 'a distinct shadow pattern or shape outdoors'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'reflections in water', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a clear reflection in any water surface outdoors', successHint: 'a visible reflection in water, clearly mirroring something'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'the colour blue outdoors', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'the most striking shade of blue in your outdoor environment', successHint: 'a clearly blue object or area in an outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'geometric patterns', difficulty: ChallengeDifficulty.medium, action: 'spot and photograph', subject: 'a strong geometric pattern found outdoors', successHint: 'a geometric pattern clearly visible in an outdoor scene'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'contrails in the sky', difficulty: ChallengeDifficulty.medium, action: 'spot and photograph', subject: 'an aircraft contrail against the open sky', successHint: 'a contrail or vapour trail clearly visible in the sky'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'moon in daylight', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'the moon while it is still visible in the daytime sky', successHint: 'the moon clearly visible in a daytime sky'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'three shades of green', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'three distinct shades of green in a single outdoor scene', successHint: 'at least three different shades of green visible in one outdoor photo'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'light through leaves', difficulty: ChallengeDifficulty.medium, action: 'photograph', subject: 'light filtering through a canopy or leaves overhead', successHint: 'light visibly passing through leaves or branches'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'weathering and age', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'something outdoors that shows the marks of time', successHint: 'an outdoor surface showing clear signs of age, weathering, or wear'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'repetition and rhythm', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a repeating element that creates visual rhythm outdoors', successHint: 'a series of repeated elements creating a pattern outdoors'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'negative space outdoors', difficulty: ChallengeDifficulty.medium, action: 'compose and photograph', subject: 'a scene where the empty space is as important as the subject', successHint: 'a photo where negative space plays a clear compositional role'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'morning mist', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'mist, fog, or atmospheric haze outdoors', successHint: 'mist or fog clearly visible in an outdoor scene'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'colour gradients in nature', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a natural gradient of colour outdoors', successHint: 'a smooth colour gradient visible in a natural outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'man-made vs natural', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'where the man-made world meets the natural world outdoors', successHint: 'a clear juxtaposition of natural and human-made elements outdoors'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'rainbows and light refraction', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'a rainbow, prism effect, or other light refraction outdoors', successHint: 'a rainbow or clear light-refraction effect visible outdoors'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'wind in motion', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'something outdoors clearly being moved by the wind', successHint: 'grass, branches, water, or another element visibly in motion from wind'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'layers of depth', difficulty: ChallengeDifficulty.medium, action: 'compose and photograph', subject: 'a scene with a clear foreground, midground, and background outdoors', successHint: 'an outdoor photo with visually distinct near, middle, and far layers'),
    ChallengeSeed(category: ChallengeCategory.observation, theme: 'texture under raking light', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a textured surface lit from the side to emphasize its texture', successHint: 'a surface outdoors where low, angled light reveals its texture clearly'),
  ];

  static const List<ChallengeSeed> _exerciseSeeds = [
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'walking a new route', difficulty: ChallengeDifficulty.easy, action: 'walk', subject: 'a route you have never taken before and photograph something you discover', successHint: 'a photo taken from an unfamiliar outdoor location'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'climbing natural elevation', difficulty: ChallengeDifficulty.medium, action: 'find and climb', subject: 'any hill, mound, or elevated ground and photograph the view from the top', successHint: 'a view from an elevated outdoor position showing the surroundings below'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'barefoot on grass', difficulty: ChallengeDifficulty.easy, action: 'remove your shoes and walk', subject: 'on grass or natural ground outdoors for at least one minute, then photograph your bare feet', successHint: 'bare feet clearly on grass or natural ground outdoors'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'stretching outdoors', difficulty: ChallengeDifficulty.easy, action: 'stretch', subject: 'your body outdoors for five minutes in a peaceful spot, then photograph where you stretched', successHint: 'an outdoor space suitable for stretching or exercise'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'finding outdoor stairs', difficulty: ChallengeDifficulty.medium, action: 'find and climb', subject: 'an outdoor staircase, steps, or ladder and photograph the top', successHint: 'outdoor steps or stairs with the photographer at or near the top'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'jogging to a landmark', difficulty: ChallengeDifficulty.medium, action: 'jog or run', subject: 'to the nearest recognizable landmark and photograph it from close up', successHint: 'a local landmark clearly photographed up close outdoors'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'a 10-minute outdoor walk', difficulty: ChallengeDifficulty.easy, action: 'walk continuously', subject: 'outdoors for at least 10 minutes and photograph where you end up', successHint: 'an outdoor location reached by walking, different from home'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'balancing on natural surface', difficulty: ChallengeDifficulty.medium, action: 'find and balance on', subject: 'a natural surface such as a log, rock, or raised root and photograph your position', successHint: 'a person balancing on a natural outdoor surface'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'outdoor yoga or stretching', difficulty: ChallengeDifficulty.easy, action: 'practice', subject: 'a simple yoga pose or deep stretch in an outdoor space, then photograph the spot', successHint: 'an outdoor area used for mindful movement or stretching'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'exploring by movement', difficulty: ChallengeDifficulty.medium, action: 'explore', subject: 'a new area solely on foot for 15 minutes and photograph the most interesting thing you find', successHint: 'an interesting outdoor discovery made while walking or moving'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'sitting on a bench outdoors', difficulty: ChallengeDifficulty.easy, action: 'find and sit on', subject: 'a bench or seat outdoors with a view you enjoy, and photograph the scene', successHint: 'an outdoor view from a seated position, such as a bench'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'walking and collecting', difficulty: ChallengeDifficulty.easy, action: 'walk and collect', subject: 'five interesting natural objects found on the ground and arrange them for a photo', successHint: 'five natural objects arranged together, found outdoors'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'cycling to somewhere new', difficulty: ChallengeDifficulty.medium, action: 'cycle', subject: 'to a spot you have not been to before and photograph it', successHint: 'a bicycle and an outdoor location reached by cycling'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'skipping or hopping outdoors', difficulty: ChallengeDifficulty.easy, action: 'skip, hop, or jump', subject: 'along an outdoor path for at least one minute, then photograph where you did it', successHint: 'an outdoor path or open space suited to skipping or hopping'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'a lap around a landmark', difficulty: ChallengeDifficulty.medium, action: 'walk or jog a full lap around', subject: 'a local landmark, park, or block, then photograph it from a new side', successHint: 'a landmark or park photographed from a side you do not usually see'),
    ChallengeSeed(category: ChallengeCategory.exercise, theme: 'walking backward mindfully', difficulty: ChallengeDifficulty.medium, action: 'walk backward slowly and carefully', subject: 'for 20 steps in a safe outdoor space, then photograph what you noticed behind you', successHint: 'a safe outdoor space suited to slow, mindful movement'),
  ];

  static const List<ChallengeSeed> _explorationSeeds = [
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'street art and murals', difficulty: ChallengeDifficulty.easy, action: 'explore and find', subject: 'street art, a mural, or painted wall in your area', successHint: 'street art or a mural clearly visible on a wall or surface outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'colorful doors', difficulty: ChallengeDifficulty.easy, action: 'explore and find', subject: 'the most interesting or colourful door in your neighbourhood', successHint: 'a distinctive painted, carved, or decorated outdoor door'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'interesting architecture', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a building with interesting or beautiful architectural details', successHint: 'architectural detail of a building clearly photographed from outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'hidden alleys and passages', difficulty: ChallengeDifficulty.medium, action: 'explore and find', subject: 'a narrow alley, passage, or hidden path in your area', successHint: 'a narrow alley or passage entrance visible in an urban setting'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'community noticeboards', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a public noticeboard or community message board', successHint: 'a public noticeboard or bulletin board with messages or notices'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'oldest buildings', difficulty: ChallengeDifficulty.medium, action: 'explore and find', subject: 'what appears to be the oldest building in your immediate area', successHint: 'an older or historic-looking building photographed from the outside'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'public fountains and sculptures', difficulty: ChallengeDifficulty.easy, action: 'explore and find', subject: 'a public fountain, statue, or outdoor sculpture', successHint: 'a public fountain, statue, or outdoor sculpture clearly visible'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'benches with views', difficulty: ChallengeDifficulty.medium, action: 'explore and find', subject: 'a bench positioned to enjoy a particularly good view', successHint: 'a bench with a clear view of something interesting or scenic outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'signs that make you smile', difficulty: ChallengeDifficulty.easy, action: 'explore and find', subject: 'a sign, notice, or message that genuinely makes you smile', successHint: 'a sign, poster, or written message in a public space'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'local landmarks', difficulty: ChallengeDifficulty.easy, action: 'explore and find', subject: 'a local landmark, monument, or well-known feature of your area', successHint: 'a recognizable local landmark photographed from outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'community gardens', difficulty: ChallengeDifficulty.medium, action: 'find and explore', subject: 'a community garden, allotment, or shared green growing space', successHint: 'a community garden or shared outdoor growing space'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'transition zones', difficulty: ChallengeDifficulty.medium, action: 'explore and find', subject: 'a place where one kind of environment gives way to another', successHint: 'a visible transition between two different environments outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'somewhere never visited before', difficulty: ChallengeDifficulty.medium, action: 'go somewhere', subject: 'you have genuinely never visited before and photograph what you find', successHint: 'a location you have not been to before, showing its character'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'a local market or stall', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a local market, market stall, or street vendor', successHint: 'a market, stall, or vendor set up outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'distinctive mailboxes or postboxes', difficulty: ChallengeDifficulty.easy, action: 'explore and find', subject: 'the most distinctive or unusual mailbox or postbox nearby', successHint: 'a mailbox or postbox with a distinctive design, photographed outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'a public transit stop', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a bus stop, train platform, or transit stop with character', successHint: 'a public transit stop or its surroundings, photographed outdoors'),
    ChallengeSeed(category: ChallengeCategory.exploration, theme: 'a shortcut never taken', difficulty: ChallengeDifficulty.medium, action: 'find and walk', subject: 'a shortcut, path, or cut-through you have never used before', successHint: 'a path or shortcut photographed while walking it for the first time'),
  ];

  static const List<ChallengeSeed> _photographySeeds = [
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'water reflections', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a clear reflection in any body of water outdoors', successHint: 'a distinct reflection visible in water such as a pond, puddle, or lake'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'macro close-ups', difficulty: ChallengeDifficulty.medium, action: 'get as close as possible and photograph', subject: 'something tiny outdoors in macro detail', successHint: 'an extreme close-up of a small natural object showing fine detail'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'framing with nature', difficulty: ChallengeDifficulty.medium, action: 'find a natural frame and photograph', subject: 'your main subject through branches, leaves, or an archway', successHint: 'a subject framed by natural elements such as branches or leaves'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'leading lines', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'strong leading lines created by a path, road, fence, or river outdoors', successHint: 'converging lines drawing the eye into the frame in an outdoor scene'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'looking straight up', difficulty: ChallengeDifficulty.easy, action: 'stand outside and photograph', subject: 'directly overhead — sky, trees, buildings, or whatever is above you', successHint: 'a photo taken by pointing the camera directly upward from outdoors'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'shadow self-portrait', difficulty: ChallengeDifficulty.medium, action: 'use your shadow as the subject and photograph', subject: 'a creative self-portrait using only your shadow outdoors', successHint: 'a shadow of a person clearly visible on an outdoor surface'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'silhouettes', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a tree, structure, or figure as a silhouette against a bright sky', successHint: 'a clearly defined silhouette against a bright sky or light background'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'natural patterns', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a repeating natural pattern such as scales, petals, or bark', successHint: 'a repeating pattern found in nature, clearly showing the pattern'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'golden hour plants', difficulty: ChallengeDifficulty.hard, action: 'go outdoors and photograph', subject: 'a plant backlit by golden hour sunlight during the first or last hour of daylight', successHint: 'a plant backlit by warm golden light with visible light glow or halo'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'colour gradient', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a natural or outdoor scene that shows a beautiful gradient of colour', successHint: 'a visible colour gradient in an outdoor scene, from light to dark or one colour to another'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'texture contrasts', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'two strongly contrasting textures side by side outdoors', successHint: 'two clearly different textures visible together in a single outdoor photo'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'unusual angle', difficulty: ChallengeDifficulty.easy, action: 'photograph', subject: 'a familiar outdoor scene from an unusual or unexpected angle', successHint: 'a photo taken from a clearly unconventional angle such as ground level or from behind'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'rule of thirds practice', difficulty: ChallengeDifficulty.medium, action: 'compose and photograph', subject: 'an outdoor subject placed off-centre using the rule of thirds', successHint: 'a deliberately off-centre composition of an outdoor subject'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'motion blur', difficulty: ChallengeDifficulty.hard, action: 'photograph', subject: 'something moving outdoors — water, leaves, or people — to capture a sense of motion', successHint: 'a photo showing clear motion blur of a moving outdoor subject'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'built for black and white', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a scene with strong contrast and shape that would work well in black and white', successHint: 'a high-contrast outdoor scene with strong shapes or tones'),
    ChallengeSeed(category: ChallengeCategory.photography, theme: 'reflections in glass or metal', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a reflection in a window, car, or metal surface outdoors', successHint: 'a clear reflection visible in glass or a metal surface outdoors'),
  ];

  static const List<ChallengeSeed> _mindfulnessSeeds = [
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'sitting in stillness', difficulty: ChallengeDifficulty.easy, action: 'find a quiet spot, sit still for 5 minutes, then photograph', subject: 'where you chose to sit and what drew you there', successHint: 'a peaceful outdoor spot where someone has sat or could sit in stillness'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'listening with eyes closed', difficulty: ChallengeDifficulty.easy, action: 'stand outside, close your eyes and listen for one minute, then photograph', subject: 'the source of the most interesting sound you heard', successHint: 'the outdoor source of an interesting natural or ambient sound'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'breathing in fresh air', difficulty: ChallengeDifficulty.easy, action: 'find a spot with clean air, take five slow deep breaths, then photograph', subject: 'the view around you in that peaceful moment', successHint: 'an outdoor scene photographed from a peaceful, calming location'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'watching clouds move', difficulty: ChallengeDifficulty.easy, action: 'lie or sit outside and watch the clouds for two minutes, then photograph', subject: 'the sky as it looks in that moment', successHint: 'the sky with clouds, photographed from outdoors'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'something that represents calm', difficulty: ChallengeDifficulty.easy, action: 'walk outside and find', subject: 'a scene, object, or place that genuinely makes you feel calm, and photograph it', successHint: 'an outdoor scene or object that conveys calm or peaceful atmosphere'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'gratitude in nature', difficulty: ChallengeDifficulty.easy, action: 'go outside and photograph', subject: 'something in nature that you feel genuinely grateful for today', successHint: 'a natural outdoor object or scene that inspires gratitude'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'smallest beautiful thing', difficulty: ChallengeDifficulty.medium, action: 'slow down and look closely outdoors to find', subject: 'something tiny that most people would walk past, and photograph it', successHint: 'a small, easily overlooked detail photographed in an outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'earth contact', difficulty: ChallengeDifficulty.easy, action: 'place your hand on soil, grass, or bark outdoors and photograph', subject: 'the moment of connection between you and the natural world', successHint: 'a hand in contact with a natural outdoor surface such as soil, grass, or bark'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'signs of the season', difficulty: ChallengeDifficulty.easy, action: 'go outside and look for visible signs of the current season, then photograph', subject: 'something that perfectly captures this moment in the year', successHint: 'an outdoor detail clearly associated with the current season'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'beauty in ordinary', difficulty: ChallengeDifficulty.medium, action: 'look at everyday outdoor objects with fresh eyes and photograph', subject: 'something ordinary that is actually beautiful on closer inspection', successHint: 'an ordinary outdoor object photographed to reveal its unexpected beauty'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'full presence outdoors', difficulty: ChallengeDifficulty.easy, action: 'go outside with no agenda and spend 5 minutes simply noticing, then photograph', subject: 'the single thing that caught your attention most in that time', successHint: 'an outdoor detail that caught the eye during a moment of mindful observation'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'touching different textures', difficulty: ChallengeDifficulty.easy, action: 'touch 10 different outdoor surfaces mindfully, then photograph', subject: 'the texture that surprised or delighted you most', successHint: 'an outdoor surface texture photographed in close detail'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'a quiet corner discovered', difficulty: ChallengeDifficulty.easy, action: 'seek out and photograph', subject: 'the quietest, most peaceful corner you can find nearby', successHint: 'a quiet, peaceful outdoor corner or nook'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'listening to water', difficulty: ChallengeDifficulty.medium, action: 'find flowing or moving water, listen for one minute, then photograph', subject: 'the water you listened to', successHint: 'flowing or moving water such as a stream, fountain, or waves'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'back against a tree', difficulty: ChallengeDifficulty.easy, action: 'sit with your back against a tree for a few minutes, then photograph', subject: 'the tree and the view from where you sat', successHint: 'a tree suitable for sitting against, photographed outdoors'),
    ChallengeSeed(category: ChallengeCategory.mindfulness, theme: 'a five-senses pause', difficulty: ChallengeDifficulty.medium, action: 'pause outdoors and notice one thing for each of your senses, then photograph', subject: 'whichever one stood out the most', successHint: 'an outdoor detail that stood out during a mindful sensory pause'),
  ];

  static const List<ChallengeSeed> _environmentalSeeds = [
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'plant diversity count', difficulty: ChallengeDifficulty.medium, action: 'count and photograph', subject: 'as many different plant species as you can spot in a 100-metre stretch', successHint: 'multiple different plant species visible in a single outdoor area'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'pollinator habitat', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'an area that supports pollinators such as wildflowers, bee hotels, or flowering plants', successHint: 'an outdoor area with flowers or habitat clearly supporting pollinators'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'invasive vs native plants', difficulty: ChallengeDifficulty.hard, action: 'research and find', subject: 'an example of an invasive plant species near you, then photograph it', successHint: 'a plant identified as invasive growing outdoors in your local area'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'green spaces in cities', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'a pocket of greenery or urban garden that brings nature into the city', successHint: 'green plants or a garden in a clearly urban outdoor setting'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'seasonal phenology', difficulty: ChallengeDifficulty.medium, action: 'observe and photograph', subject: 'a clear seasonal environmental change happening right now', successHint: 'an outdoor scene showing a seasonal biological or environmental change'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'local species diversity', difficulty: ChallengeDifficulty.medium, action: 'explore and photograph', subject: 'three different species of plants or animals in a small outdoor area', successHint: 'at least two or three different species of plants or animals visible outdoors'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'tree canopy coverage', difficulty: ChallengeDifficulty.easy, action: 'find an area with good tree coverage and photograph', subject: 'the canopy from below, showing the trees overhead', successHint: 'a tree canopy photographed from below, showing leaves against the sky'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'natural resource use', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'an example of renewable energy, water conservation, or sustainable practice outdoors in your community', successHint: 'outdoor infrastructure or signage related to sustainability or natural resource use'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'urban farming', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'any example of food growing in an urban or suburban setting', successHint: 'food plants or an urban garden growing in a city or suburban outdoor space'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'ecological succession', difficulty: ChallengeDifficulty.hard, action: 'find and photograph', subject: 'an example of nature reclaiming a human-made space', successHint: 'plants or nature visibly growing through or over a man-made structure outdoors'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'microhabitats', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a small, self-contained microhabitat such as a rock pool, tree hollow, or mossy log', successHint: 'a compact outdoor habitat with visible signs of life'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'erosion and water flow', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'visible signs of erosion or water shaping the landscape', successHint: 'ground, rock, or a bank visibly shaped by water or erosion'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'hedgerows and wildlife corridors', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a hedgerow, tree line, or corridor that connects green spaces', successHint: 'a hedgerow or line of vegetation connecting two green areas'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'soil and composting health', difficulty: ChallengeDifficulty.easy, action: 'find and photograph', subject: 'healthy soil, leaf litter, or a compost area supporting plant life', successHint: 'visibly healthy soil or organic matter supporting growth outdoors'),
    ChallengeSeed(category: ChallengeCategory.environmental, theme: 'waterway health', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'a local stream, pond, or waterway and its surrounding plant life', successHint: 'a waterway with visible surrounding vegetation or wildlife'),
  ];

  static const List<ChallengeSeed> _microAdventureSeeds = [
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'adventure in 15 minutes from home', difficulty: ChallengeDifficulty.easy, action: 'set a timer for 15 minutes and explore', subject: 'somewhere you have not been on foot, then photograph the most interesting thing you find', successHint: 'an outdoor discovery made within a short walk of home'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'explore one block completely', difficulty: ChallengeDifficulty.easy, action: 'walk one complete block slowly and photograph', subject: 'every interesting thing you notice — the best one becomes your challenge photo', successHint: 'an interesting detail found in an urban block during slow, deliberate exploration'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'find something unexpected', difficulty: ChallengeDifficulty.medium, action: 'walk without a plan and photograph', subject: 'the most unexpected or surprising thing you encounter outdoors today', successHint: 'an unexpected outdoor find that surprises or delights'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'go somewhere never been', difficulty: ChallengeDifficulty.medium, action: 'travel to', subject: 'a street, park, or area you have genuinely never visited before, and photograph something there', successHint: 'an outdoor location you have not visited before, showing a detail or scene'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'turning left instead of right', difficulty: ChallengeDifficulty.easy, action: 'take your usual route then turn the opposite way to normal, and photograph', subject: 'something interesting you discover by going the unfamiliar way', successHint: 'an outdoor discovery made by taking an unfamiliar route'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'the most interesting thing within 500m', difficulty: ChallengeDifficulty.easy, action: 'explore within 500 metres of your current location and photograph', subject: 'the single most interesting thing you find', successHint: 'an interesting outdoor subject found within a very short distance'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'a tiny expedition to water', difficulty: ChallengeDifficulty.medium, action: 'walk to the nearest water source and photograph', subject: 'something interesting you observe there — the water, the life, or the scene', successHint: 'a water source such as a pond, stream, puddle, or fountain with something interesting to observe'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'looking up for once', difficulty: ChallengeDifficulty.easy, action: 'walk 100 metres looking only upward and photograph', subject: 'the most interesting thing you see above head height', successHint: 'something photographed at or above head height from an outdoor perspective'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'the ordinary transformed', difficulty: ChallengeDifficulty.medium, action: 'find and photograph', subject: 'something ordinary in your outdoor environment that looks extraordinary from the right angle', successHint: 'a commonplace outdoor object or scene made to look unusual or striking'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'instinct as map', difficulty: ChallengeDifficulty.medium, action: 'go outside and follow your instincts with no plan, then photograph', subject: 'where you end up and what drew you there', successHint: 'an outdoor location reached by spontaneous exploration rather than planning'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'a viewpoint you had to earn', difficulty: ChallengeDifficulty.hard, action: 'walk, climb, or find your way to a viewpoint that requires some effort, then photograph', subject: 'the view from that elevated or out-of-the-way perspective', successHint: 'a view from an elevated or non-obvious outdoor vantage point'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'explore by colour', difficulty: ChallengeDifficulty.medium, action: 'pick a colour and follow it outdoors', subject: 'wherever that colour leads you, then photograph what you find', successHint: 'an outdoor discovery found by following a single chosen colour'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'a dawn or dusk micro-adventure', difficulty: ChallengeDifficulty.hard, action: 'go outside right at dawn or dusk and photograph', subject: 'how your surroundings look in that in-between light', successHint: 'an outdoor scene photographed in dawn or dusk light'),
    ChallengeSeed(category: ChallengeCategory.microAdventure, theme: 'retrace a memory', difficulty: ChallengeDifficulty.medium, action: 'walk to a spot that holds a memory for you and photograph', subject: 'how that place looks today', successHint: 'a meaningful outdoor location photographed as it looks now'),
  ];

  // ── Seed selection ─────────────────────────────────────────────────────────

  /// Returns a seed deterministically based on [dayNumber] and [userId],
  /// ensuring variety while remaining reproducible.
  static ChallengeSeed selectSeed({
    required int dayNumber,
    required String userId,
    required ChallengeDifficulty difficulty,
  }) {
    if (_allSeeds.isEmpty) return _fallbackSeed(difficulty);

    // Combine day and user hash for spread — different users get different seeds
    // on the same day; same user gets different seeds across days.
    final userHash = userId.hashCode.abs();
    final index = ((dayNumber * 31 + userHash) % _allSeeds.length).abs();
    final candidate = _allSeeds[index];

    // If the category difficulty matches, use it; otherwise find nearest same category.
    if (candidate.difficulty == difficulty) return candidate;

    final sameCategoryWithDifficulty = _allSeeds
        .where((s) => s.category == candidate.category && s.difficulty == difficulty)
        .toList();
    if (sameCategoryWithDifficulty.isNotEmpty) {
      final i2 = (userHash + dayNumber) % sameCategoryWithDifficulty.length;
      return sameCategoryWithDifficulty[i2];
    }

    // Fallback: any seed matching the difficulty.
    final anyDifficulty =
        _allSeeds.where((s) => s.difficulty == difficulty).toList();
    if (anyDifficulty.isNotEmpty) {
      return anyDifficulty[_random.nextInt(anyDifficulty.length)];
    }

    return _allSeeds[index];
  }

  /// Selects a seed for a reroll, avoiding the [excludedTheme].
  static ChallengeSeed selectRerollSeed({
    required int dayNumber,
    required String userId,
    required ChallengeDifficulty difficulty,
    required int rerollCount,
    String? excludedTheme,
  }) {
    final candidates = _allSeeds
        .where((s) =>
            s.difficulty == difficulty &&
            (excludedTheme == null || s.theme != excludedTheme))
        .toList();

    if (candidates.isEmpty) return selectSeed(dayNumber: dayNumber, userId: userId, difficulty: difficulty);

    final userHash = userId.hashCode.abs();
    final index = ((dayNumber * 17 + userHash + rerollCount * 7) % candidates.length).abs();
    return candidates[index];
  }

  static ChallengeSeed _fallbackSeed(ChallengeDifficulty difficulty) =>
      ChallengeSeed(
        category: ChallengeCategory.nature,
        theme: 'nature observation',
        difficulty: difficulty,
        action: 'observe and photograph',
        subject: 'something beautiful in the natural world outdoors',
        successHint: 'a natural object or scene in an outdoor setting',
      );

  /// Total number of seeds in the library.
  static int get count => _allSeeds.length;
}
