import 'package:flutter/material.dart';

// TODO: apni real support details daalo
const supportPhone = '+91 00000 00000';
const supportEmail = 'support@example.com';

class Project {
  final String name, location, status, price, flats, towers;
  const Project(this.name, this.location, this.status, this.price, this.flats, this.towers);
}

const projects = [
  Project('Dabbewala & Charmakar Building', 'Ambivali, Kalyan, Thane', 'Active', '₹25.5 Lakhs', '12,132', '8'),
  Project('Shri Shakti Residency', 'Kalyan, Thane', 'Active', '₹22.0 Lakhs', '8,060', '5'),
  Project('Krutarth Heights', 'Titwala, Thane', 'Upcoming', '₹24.0 Lakhs', '4,500', '4'),
];

const projectFeatures = [
  'Affordable EMI options',
  'Modern amenities',
  'Excellent connectivity',
  'Safe & secure community',
];

class Scheme {
  final String title, subtitle, details;
  final IconData icon;
  final Color color;
  const Scheme(this.title, this.subtitle, this.details, this.icon, this.color);
}

const schemes = [
  Scheme('PMAY Urban', 'Affordable Housing for All\nEWS / LIG / MIG', 'Housing support for urban families in EWS, LIG and MIG income groups.',
      Icons.home_rounded, Color(0xFFF57C20)),
  Scheme('Credit Linked Subsidy Scheme', 'Interest Subsidy up to 6.5%\nFor eligible beneficiaries', 'Interest subsidy on home loans for eligible beneficiaries.',
      Icons.percent_rounded, Color(0xFF1649A8)),
  Scheme('Affordable Rental Housing', 'Rental support for urban poor\nWith Government assistance', 'Rental housing support for migrants and the urban poor.',
      Icons.key_rounded, Color(0xFF2E9E5B)),
  Scheme('In-situ Slum Redevelopment', 'Better homes, better lives\nFor slum dwellers', 'Redevelopment of slums on the same land with better housing.',
      Icons.apartment_rounded, Color(0xFF8E44AD)),
  Scheme('Beneficiary Led Construction', 'Build your own home\nFinancial assistance', 'Financial assistance to build or enhance your own house.',
      Icons.construction_rounded, Color(0xFFE67E22)),
];