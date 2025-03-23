import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'About CodeChat',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Empowering Developers with AI-Powered Coding Assistance',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'CodeChat is an innovative AI-driven coding assistant designed to streamline software development by providing deep, project-specific insights. Unlike generic AI chatbots, CodeChat understands the full context of your codebase, enabling developers to ask questions, receive precise answers, and even generate or refactor code efficiently.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 30),
            _buildSection(
              context,
              'How CodeChat Works',
              [
                'Upload Your Project – CodeChat processes and indexes your codebase, creating an intelligent understanding of your system.',
                'Ask Questions – Get immediate, context-aware responses about functions, dependencies, and best practices.',
                'AI-Powered Coding – Automate documentation, generate new features, and debug issues with AI assistance.',
                'Integrate with Your Workflow – Works seamlessly with VS Code, JetBrains, and other development environments.',
              ],
            ),
            const SizedBox(height: 30),
            _buildSection(
              context,
              'Why CodeChat?',
              [
                'Deep Code Understanding – Leverages AI-powered Retrieval-Augmented Generation (RAG) to provide answers tailored to your project.',
                'Boost Productivity – Reduce debugging time, accelerate onboarding, and enhance collaboration.',
                'Secure & Private – Designed to prioritize security, with optional on-premise deployment for enterprises.',
                'Future-Ready – Continuously evolving to support predictive bug fixing, AI-enhanced auto-coding, and real-time collaboration.',
              ],
            ),
            const SizedBox(height: 30),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 24.0,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  'Join the future of AI-powered software development with CodeChat. Whether you\'re an individual developer or an enterprise team, CodeChat is here to supercharge your coding experience.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<String> bulletPoints) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 16),
        ...bulletPoints.map(
          (point) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.arrow_right,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}