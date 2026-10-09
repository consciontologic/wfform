/// Canonical soft-wrapper artwork, shared by Flutter and the PNG generator.
/// Coordinates use a 100-unit square. Each row is a cubic Bezier segment
/// (control 1, control 2, endpoint), beginning and ending at (20, 19).
const wrapperCurves = <List<double>>[
  [12, 19, 7, 24, 7, 32],
  [7, 36, 7, 42, 7, 46],
  [7, 59, 13, 64, 24, 75],
  [32, 83, 38, 82, 47, 76],
  [49, 74, 51, 74, 54, 76],
  [63, 82, 69, 83, 77, 75],
  [80, 72, 84, 68, 87, 65],
  [92, 59, 94, 53, 94, 46],
  [94, 42, 94, 36, 94, 32],
  [94, 24, 88, 19, 81, 19],
  [80, 19, 80, 19, 79, 19],
  [72, 19, 67, 25, 67, 32],
  [67, 35, 67, 39, 67, 42],
  [67, 51, 64, 55, 59, 53],
  [52, 49, 47, 49, 41, 53],
  [35, 56, 31, 50, 31, 42],
  [31, 39, 31, 35, 31, 32],
  [31, 24, 26, 19, 20, 19],
];

const brandInk = 0xff302d34;
const brandPaper = 0xfff6f3ec;
const brandLavender = 0xffb7a8c9;
const brandDarkLavender = 0xffc8b8dc;
const brandLightSurface = 0xffdcd3e6;
const brandDarkSurface = 0xff302b38;
const wrapperStroke = 4.2;
const wrapperCore = (left: 41.0, top: 25.0, width: 19.0, height: 18.0);
const wrapperCoreRadius = 4.5;
