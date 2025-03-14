import 'package:flutter/material.dart';
import 'package:flutter_google_maps_webservices/places.dart';

class PredictionTile extends StatelessWidget {
  final Prediction prediction;
  final ValueChanged<Prediction>? onTap;

  PredictionTile({required this.prediction, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.location_on),
      title: RichText(
        text: TextSpan(
          children: _buildPredictionText(context),
        ),
      ),
      onTap: () {
        if (onTap != null) {
          onTap!(prediction);
        }
      },
    );
  }

  List<TextSpan> _buildPredictionText(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium!.color;
    final description = prediction.description ?? '';

    // If there is no matched strings, but there are predicts. (Not sure if this happens though)
    if (prediction.matchedSubstrings.isEmpty) {
      return [
        TextSpan(
          text: description,
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w300),
        ),
      ];
    }

    final result = <TextSpan>[];
    MatchedSubstring matchedSubString = prediction.matchedSubstrings[0];
    final offset = matchedSubString.offset as int;
    final length = matchedSubString.length as int;

    // There is no matched string at the beginning.
    if (offset > 0) {
      result.add(
        TextSpan(
          text: description.substring(0, offset),
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w300),
        ),
      );
    }

    // Matched strings.
    result.add(
      TextSpan(
        text: description.substring(offset, offset + length),
        style: TextStyle(
            color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );

    // Other strings.
    if (offset + length < description.length) {
      result.add(
        TextSpan(
          text: description.substring(offset + length),
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w300),
        ),
      );
    }

    return result;
  }
}
