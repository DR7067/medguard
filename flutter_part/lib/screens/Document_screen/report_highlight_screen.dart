import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ReportHighlightScreen extends StatelessWidget {
  final String imagePath;
  final double imageWidth;
  final double imageHeight;
  final List<Map<String, dynamic>> boxes;
  final Uint8List? imageBytes;
  final List<Map<String, dynamic>> abnormalResults;

  const ReportHighlightScreen({
    super.key,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.boxes,
    this.imageBytes,
    this.abnormalResults = const [],
  });

  @override
  Widget build(BuildContext context) {
    final dietPlans = _buildDietPlans(abnormalResults);

    return Scaffold(
      appBar: AppBar(title: const Text("Abnormal Highlights")),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (imageWidth <= 0 || imageHeight <= 0) {
                  return const Center(child: Text("Invalid image size."));
                }

                final scale = min(
                  constraints.maxWidth / imageWidth,
                  constraints.maxHeight / imageHeight,
                );
                final renderWidth = imageWidth * scale;
                final renderHeight = imageHeight * scale;

                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Center(
                    child: SizedBox(
                      width: renderWidth,
                      height: renderHeight,
                      child: Stack(
                        children: [
                          if (imageBytes != null)
                            Image.memory(
                              imageBytes!,
                              width: renderWidth,
                              height: renderHeight,
                              fit: BoxFit.fill,
                            )
                          else if (imagePath.isNotEmpty)
                            Image.file(
                              File(imagePath),
                              width: renderWidth,
                              height: renderHeight,
                              fit: BoxFit.fill,
                            )
                          else
                            const Center(
                              child: Text("Report image not available."),
                            ),
                          ...boxes.map((box) {
                            const double pad = 3.0;
                            final rawLeft =
                                (box["left"] as num).toDouble() * scale - pad;
                            final rawTop =
                                (box["top"] as num).toDouble() * scale - pad;
                            final rawRight =
                                rawLeft +
                                (box["width"] as num).toDouble() * scale +
                                (pad * 2);
                            final rawBottom =
                                rawTop +
                                (box["height"] as num).toDouble() * scale +
                                (pad * 2);

                            final clampedLeft = max(
                              0.0,
                              min(rawLeft, renderWidth),
                            );
                            final clampedTop = max(
                              0.0,
                              min(rawTop, renderHeight),
                            );
                            final clampedRight = max(
                              0.0,
                              min(rawRight, renderWidth),
                            );
                            final clampedBottom = max(
                              0.0,
                              min(rawBottom, renderHeight),
                            );

                            final width = max(0.0, clampedRight - clampedLeft);
                            final height = max(0.0, clampedBottom - clampedTop);
                            return Positioned(
                              left: clampedLeft,
                              top: clampedTop,
                              width: width,
                              height: height,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.75),
                                    width: 1.2,
                                  ),
                                  // Keep text readable by avoiding a filled overlay.
                                  color: Colors.transparent,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (dietPlans.isNotEmpty)
            Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Easy Food Tips",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: dietPlans.length,
                      separatorBuilder: (_, separatorIndex) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final plan = dietPlans[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${plan.test} (${plan.status.toUpperCase()})",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text("Eat more: ${plan.add.join(", ")}"),
                                Text("Eat less: ${plan.limit.join(", ")}"),
                                Text(
                                  "Tip: ${plan.note}",
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Simple tips only. Please confirm with your doctor/dietitian.",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_DietPlan> _buildDietPlans(List<Map<String, dynamic>> rows) {
    final plans = <_DietPlan>[];
    final seen = <String>{};

    for (final item in rows) {
      final rawTest = item["test"]?.toString();
      if (rawTest == null || rawTest.trim().isEmpty) {
        continue;
      }

      final test = rawTest.trim().toUpperCase();
      final status = _deriveStatus(item);
      final key = "$test:$status";
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);

      plans.add(_dietPlanFor(test, status));
    }

    return plans;
  }

  String _deriveStatus(Map<String, dynamic> item) {
    final value = (item["value"] as num?)?.toDouble();
    final range = item["range"];

    if (value != null && range is List && range.length >= 2) {
      final minValue = (range[0] as num?)?.toDouble();
      final maxValue = (range[1] as num?)?.toDouble();

      if (minValue != null && value < minValue) return "low";
      if (maxValue != null && value > maxValue) return "high";
    }

    final flag = item["flag"]?.toString().toUpperCase();
    if (flag == "H" || flag == "HH" || flag == "HIGH") {
      return "high";
    }
    if (flag == "L" || flag == "LL" || flag == "LOW") {
      return "low";
    }

    return "abnormal";
  }

  _DietPlan _dietPlanFor(String test, String status) {
    if ((test == "HEMOGLOBIN" || test == "RBC") && status == "low") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["palak", "egg", "fish/chicken", "jaggery", "nimbu"],
        limit: ["tea/coffee with meals", "packaged snacks"],
        note: "Add nimbu with meals.",
      );
    }

    if ((test == "TOTAL CHOLESTEROL" || test == "LDL CHOLESTEROL") &&
        status == "high") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["sabzi", "fish", "nuts", "whole wheat roti", "brown rice"],
        limit: ["fried foods", "ghee/butter", "red meat", "bakery items"],
        note: "Cook with less oil.",
      );
    }

    if (test == "TRIGLYCERIDES" && status == "high") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["sabzi", "whole wheat roti", "brown rice", "fish"],
        limit: ["sweet drinks", "mithai", "white bread/maida", "alcohol"],
        note: "Avoid sugary drinks.",
      );
    }

    if (test == "HDL CHOLESTEROL" && status == "low") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["olive oil", "nuts", "seeds", "avocado", "fatty fish"],
        limit: ["trans-fat snacks", "deep-fried foods"],
        note: "Add a short daily walk.",
      );
    }

    if ((test == "UREA" || test == "CREATININE") && status == "high") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["water (if allowed)", "sabzi", "fruits", "roti/rice"],
        limit: ["extra salt", "processed meat", "very high-protein meals"],
        note: "Follow your doctor’s kidney diet advice.",
      );
    }

    if (test == "URIC ACID" && status == "high") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["water", "milk/curd", "sabzi", "cucumber"],
        limit: ["organ meats", "red meat", "beer", "sweet drinks"],
        note: "Avoid organ meats.",
      );
    }

    if (test == "SODIUM") {
      if (status == "high") {
        return _DietPlan(
          test: test,
          status: status,
          add: ["home-cooked meals", "fresh foods"],
          limit: ["pickles", "chips", "instant soups", "packaged foods"],
          note: "Taste food before adding salt.",
        );
      }
      if (status == "low") {
        return _DietPlan(
          test: test,
          status: status,
          add: ["regular meals", "electrolyte fluids if advised"],
          limit: ["only plain water all day"],
          note: "Low sodium can be serious; follow your doctor.",
        );
      }
    }

    if (test == "POTASSIUM") {
      if (status == "high") {
        return _DietPlan(
          test: test,
          status: status,
          add: ["apple", "rice", "gobi"],
          limit: ["banana", "orange juice", "coconut water", "potato"],
          note: "Use kidney plan if you have one.",
        );
      }
      if (status == "low") {
        return _DietPlan(
          test: test,
          status: status,
          add: ["banana", "orange", "potato", "palak"],
          limit: ["skipping meals", "ultra-processed foods"],
          note: "Add these foods slowly.",
        );
      }
    }

    if ((test == "CALCIUM" || test == "PHOSPHORUS") && status == "low") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["milk/curd", "paneer", "til", "leafy greens"],
        limit: ["cola/soft drinks", "salty packaged foods"],
        note: "Get some sunlight if possible.",
      );
    }

    if ((test == "ALBUMIN" || test == "TOTAL PROTEIN") && status == "low") {
      return _DietPlan(
        test: test,
        status: status,
        add: ["eggs", "paneer", "fish/chicken", "curd"],
        limit: ["skipping meals", "very low-protein diets"],
        note: "Have protein at each meal.",
      );
    }

    return _DietPlan(
      test: test,
      status: status,
      add: ["vegetables", "fruits", "whole grains", "lean protein"],
      limit: ["fried foods", "added sugar", "high-salt processed foods"],
      note: "Simple start. Ask your doctor for changes.",
    );
  }
}

class _DietPlan {
  final String test;
  final String status;
  final List<String> add;
  final List<String> limit;
  final String note;

  const _DietPlan({
    required this.test,
    required this.status,
    required this.add,
    required this.limit,
    required this.note,
  });
}
