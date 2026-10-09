/// Canonical Open Cradle artwork shared by Flutter and the PNG generator.
/// Coordinates use a 100-unit square. Each closed, filled ribbon contour starts
/// at (x, y); each curve holds control 1, control 2, and endpoint coordinates.
/// The two contours leave a transparent fold seam at the lower left.
const cradleBands = <({double x, double y, List<List<double>> curves})>[
  (
    x: 36,
    y: 14,
    curves: [
      [42, 14, 45, 23, 39, 28],
      [34, 32, 29, 35, 24, 38],
      [21, 40, 20, 43, 20, 49],
      [20, 54, 20, 59, 20, 64],
      [20, 74, 20, 80, 25, 84],
      [13, 79, 7, 75, 7, 64],
      [7, 60, 7, 54, 7, 49],
      [7, 36, 10, 30, 19, 24],
      [24, 20, 29, 17, 32, 15],
      [33, 14, 35, 14, 36, 14],
    ],
  ),
  (
    x: 22,
    y: 66,
    curves: [
      [30, 72, 35, 73, 43, 73],
      [50, 73, 56, 73, 64, 73],
      [75, 73, 82, 66, 82, 59],
      [82, 55, 80, 51, 78, 47],
      [74, 40, 78, 35, 83, 35],
      [86, 35, 88, 37, 90, 41],
      [93, 47, 95, 53, 95, 59],
      [95, 75, 81, 85, 65, 85],
      [55, 85, 44, 85, 34, 85],
      [26, 85, 22, 81, 22, 72],
      [22, 70, 22, 68, 22, 66],
    ],
  ),
];

const cradleNodes = <({double x, double y, double radius})>[
  (x: 40, y: 52, radius: 11),
  (x: 64, y: 35, radius: 9),
];
const cradleLinkWidth = 6.0;

const brandInk = 0xff302d34;
const brandPaper = 0xfff6f3ec;
const brandLavender = 0xffb7a8c9;
const brandDarkLavender = 0xffc8b8dc;
