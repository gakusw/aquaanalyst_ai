class NutritionResult {
  final double protein;
  final double carbs;
  final double fat;
  final String reason;
  final String? description;

  NutritionResult({
    required this.protein, 
    required this.carbs, 
    required this.fat, 
    required this.reason, 
    this.description
  });
}
