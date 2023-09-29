import 'dart:convert';

import 'package:build_a_story/models/completed_section.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CompletedSectionWidget extends StatelessWidget {
  final CompletedSection completedSection;

  const CompletedSectionWidget(this.completedSection, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 500,
          child: Text(
            completedSection.storyText,
            style: GoogleFonts.lato(),
            textAlign: TextAlign.center,
          ),
        ),
        Container(
            height: 500,
            width: 500,
            margin: EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(6)),
                child:
                    Image.memory(base64Decode(completedSection.base64Image))))
      ],
    );
  }
}
