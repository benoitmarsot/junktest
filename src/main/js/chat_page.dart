import 'dart:async';

import 'package:codechatui/src/services/auth_provider.dart';
import 'package:codechatui/src/services/message_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // Add this import for keyboard keys
import 'package:codechatui/src/models/project.dart';
import 'package:codechatui/src/models/message.dart';
import 'package:codechatui/src/models/discussion.dart';
import 'package:codechatui/src/services/discussion_service.dart';
import 'package:codechatui/src/widgets/ai_response_widget.dart';
import 'package:codechatui/src/widgets/user_message_bubble.dart';
import 'package:provider/provider.dart';

class ChatPage extends StatefulWidget {
  final Project project;
  final VoidCallback onThemeToggle; 
  
  const ChatPage({super.key, required this.project, required this.onThemeToggle});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  late AuthProvider authProvider;
  late TabController _tabController;
  late DiscussionService _discussionService;
  late MessageService _messageService;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();  // Add this for keyboard handling
  final List<Message> _messages = [];
  
  // Panel control variables
  double _leftPanelWidth = 250.0; // Default width
  bool _isLeftPanelVisible = true;
  
  // Discussion tracking
  int _selectedDiscussionId = 0; // 0 means no discussion selected
  List<Discussion> _discussions = [];
   
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
     authProvider = Provider.of<AuthProvider>(context, listen: false);
    _tabController = TabController(length: 2, vsync: this);
    _discussionService = DiscussionService(authProvider: authProvider);
    _messageService = MessageService(authProvider: authProvider);
    
    // Method 1: Using addPostFrameCallback (recommended)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDiscussions();
    });
    
    // Alternative method 2: Using Future.microtask
    // Future.microtask(() {
    //   _loadDiscussions();
    // });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();  // Don't forget to dispose the focus node
    super.dispose();
  }

  // Load discussions for the current project
  Future<void> _loadDiscussions() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final discussions = await _discussionService.getDiscussionsByProject(widget.project.projectId);
      setState(() {
        _discussions = discussions;
      });
    } catch (e) {
      // Show error to user
      if(mounted) {
        print("Error loading discussions: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load discussions: $e'))
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Load messages for a specific discussion
  Future<void> _selectDiscussion(int discussionId) async {
    if (_selectedDiscussionId == discussionId) return;
    
    setState(() {
      _isLoading = true;
      _messages.clear();
    });
    
    try {
      final messages = await _messageService.getMessagesByDiscussionId(discussionId);
      setState(() {
        _messages.addAll(messages);
        _selectedDiscussionId = discussionId;
      });
      
      // Scroll to bottom after loading messages
      _scrollToBottom();
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load messages: $e'))
        );
      }
      setState(() {
        _selectedDiscussionId = 0;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    // Save message text and clear input
    final messageText = _messageController.text;
    _messageController.clear();
    
    // Create new discussion if none selected
    if(_selectedDiscussionId == 0) {
      try {
        final newDiscussion = await _discussionService.createDiscussion(
          widget.project.projectId, 'Discussion ${_discussions.length + 1}'
        );
        _selectedDiscussionId = newDiscussion.did;
        _discussions.insert(0, newDiscussion);
      } catch (e) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create discussion: $e'))
          );
        }
        return;
      }
      finally {
        
        setState(() {
          _isLoading = false;
        });
      }
    }
    
    // Send user message
    final msgRequest = MessageCreateRequest(
      did: _selectedDiscussionId,
      role: "user",
      message: messageText,
    );
    
    try {
      // Add user message to UI
      final userMsg = await _discussionService.askQuestion(msgRequest);
      setState(() {
        _messages.add(userMsg);
      });
      _scrollToBottom();
      
      // Add a temporary "thinking" message
      Message thinkingMsg = Message(
        discussionId: _selectedDiscussionId,
        role: "assistant",
        text: "Thinking...",
        isLoading: true,
      );
      
      setState(() {
        _messages.add(thinkingMsg);
      });
      _scrollToBottom();
      
      // Show dynamic thinking animation
      int index = _messages.length - 1;
      int dots = 0;
      
      Timer? progressTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        dots = (dots + 1) % 4;
        String thinking = "Thinking ${".".padLeft(dots, '.')}";
        
        setState(() {
          _messages[index] = Message(
            discussionId: _selectedDiscussionId,
            role: "assistant", 
            text: thinking,
            isLoading: true,
          );
        });
      });
      
      // Get actual AI response
      try {
        final message = await _discussionService.answerQuestion(_selectedDiscussionId);
        
        // Cancel the progress timer
        progressTimer.cancel();
        
        if (mounted) {
          setState(() {
            // Remove the temporary message
            _messages.removeWhere((message) => message.isLoading == true);
            // Add the real response
            _messages.add(message);
          });
          _scrollToBottom();
        }
      } catch (aiError) {
        // Cancel the progress timer
        progressTimer.cancel();
        
        if (mounted) {
          setState(() {
            // Remove the temporary message
            _messages.removeWhere((message) => message.isLoading == true);
            
            // Add error message
            _messages.add(Message(
              discussionId: _selectedDiscussionId,
              role: "assistant",
              text: "Sorry, I encountered an error: $aiError",
            ));
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to get AI response: $aiError'))
          );
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e'))
        );
      }
    }
  }
  
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleLeftPanel() {
    setState(() {
      _isLeftPanelVisible = !_isLeftPanelVisible;
    });
  }
  String minPanelEmptyMessage() => 'Start a new conversation${_discussions.isEmpty ? ' or select one from history' : ''}';

  // Handle key events for message input
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        // Insert a new line at cursor position when shift+Enter is pressed
        final text = _messageController.text;
        final selection = _messageController.selection;
        final newText = '${text.substring(0, selection.start)}\n${text.substring(selection.end)}';
        
        _messageController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: selection.start + 1,
          ),
        );
        return KeyEventResult.handled;
      } else if (!HardwareKeyboard.instance.isShiftPressed) {
        // Submit message on plain Enter (not handling shift+enter for now)
        // Call async method to send message and do not wait for it
        _sendMessage();
        return KeyEventResult.handled;  
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        leading: IconButton(
          icon: Icon(_isLeftPanelVisible ? Icons.menu_open : Icons.menu),
          onPressed: _toggleLeftPanel,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.of(context).pop(); // Navigate back to home page
            },
            tooltip: 'Back to Home',
          ),
  
          IconButton(
            icon: const Icon(Icons.add_comment),
            onPressed: () {
              setState(() {
                _selectedDiscussionId = 0;
                _messages.clear();
              });
            },
            tooltip: 'New Discussion',
          ),
           IconButton(
            icon: const Icon(Icons.light_mode),
            onPressed: widget.onThemeToggle,
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: Row(
        children: [
          // Left side - Tab controller for historical discussions
          if (_isLeftPanelVisible)
            SizedBox(
              width: _leftPanelWidth,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'History'),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Favorites'),
                            SizedBox(width: 4),
                            Tooltip(
                              message: 'Favorite discussions remain saved beyond 30 days.',
                              child: Icon(Icons.info_outline, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // History tab with discussions
                        _isLoading 
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              children: [
                                
                                Expanded(
                                  child: _discussions.isEmpty
                                    ? const Center(child: Text('No discussions found'))
                                    : _getDiscussionsList(),
                                ),
                              ],
                            ),

                        // Favorites tab - similarly
                        _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              children: [
                                // Existing favorites list
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _discussions.where((d) => d.isFavorite).length,
                                    itemBuilder: (context, index) {
                                      final favorites = _discussions.where((d) => d.isFavorite).toList();
                                      return Tooltip(
                                        message: 'Created: ${_formatDate(favorites[index].created)}\n'
                                                '${favorites[index].name}',
                                        preferBelow: false,
                                        verticalOffset: 20,
                                        child: ListTile(
                                          title: Text(favorites[index].name),
                                          subtitle: Text(_formatDate(favorites[index].created)),
                                          selected: _selectedDiscussionId == favorites[index].did,
                                          onTap: () => _selectDiscussion(favorites[index].did),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Resizable divider
          if (_isLeftPanelVisible)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _leftPanelWidth += details.delta.dx;
                  // Enforce minimum and maximum width constraints
                  _leftPanelWidth = _leftPanelWidth.clamp(220.0, MediaQuery.of(context).size.width * 0.5);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Container(
                  width: 8,
                  height: double.infinity,
                  color: colorScheme.secondaryContainer,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:  [
                        Icon(Icons.drag_indicator, size: 16),
                        SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          
          // Right side - Chat area
          Expanded(
            child: Column(
              children: [
                // Chat messages area with loading indicator
                Expanded(
                  child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(child: Text(
                            'Start a new conversation${_discussions.isNotEmpty ? ' or select one from history' : ''}'
                          ))
                        : ListView.builder(
                          controller: _scrollController,
                          itemCount: _messages.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return message.role == "user"
                              ? UserMessageBubble(message: message)
                              : AIResponseWidget(message: message);
                          },
                        ),
                ),
                // Input area
                Container(
                  padding: const EdgeInsets.all(8.0),
             
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode..onKeyEvent = _handleKeyEvent,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: 'Type your question...',
                              border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0), // Rounded corners
                              borderSide: BorderSide.none,               // No border
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            // helperText: 'Press Enter to send, Shift+Enter for new line',
                          ),
                          minLines: 1,
                          maxLines: 20,
                          // Using focusNode.onKeyEvent to handle keyboard events
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Add this helper method to format dates nicely
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  
  ListView _getDiscussionsList() {
    return ListView.builder(
      itemCount: _discussions.length,
      itemBuilder: (context, index) {
        final discussion = _discussions[index];
        return Tooltip(
          message: 'Created: ${_formatDate(discussion.created)}\n'
                  '${discussion.description.isNotEmpty ? discussion.description : discussion.name}',
          preferBelow: true,
          verticalOffset: 20,
          child: ListTile(
            minLeadingWidth: 8,
            horizontalTitleGap: 4,
            contentPadding: const EdgeInsets.only(left: 4, right: 0), // Remove right padding completely
            dense: true, // Make the ListTile more compact overall
            leading: Padding(
              padding: const EdgeInsets.only(left: 0, right:2),
              child: InkWell(
                onTap: () => _toggleFavorite(discussion),
                child: Icon(
                  discussion.isFavorite ? Icons.star : Icons.star_border,
                  color: discussion.isFavorite ? Colors.amber : Colors.grey,
                  size: 14,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    discussion.name,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                SizedBox(
                  width: 16,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert,
                      size: 16,
                    ),
                    iconSize: 16,
                    tooltip: 'Discussion options',
                    onSelected: (value) => _handleDiscussionAction(value, discussion),
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'suggest_name',
                        child: ListTile(
                          leading: Icon(Icons.auto_awesome),
                          title: Text('Auto-catalog'),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Rename & describe'),
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text('Delete', style: TextStyle(color: Colors.red)),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

              ],
            ),
            // Remove the trailing property since we've embedded it in the title row
            trailing: null,
            selected: _selectedDiscussionId == discussion.did,
            onTap: () => _selectDiscussion(discussion.did),
          ),
        );
      },
    );
  }
  
  // Handler for discussion context menu actions
  void _handleDiscussionAction(String action, Discussion discussion) async {
    switch (action) {
      case 'suggest_name':
        _suggestDiscussionName(discussion);
      case 'rename':
        _renameDiscussion(discussion);
      case 'delete':
        _deleteDiscussion(discussion);
    }
  }

  // Method to suggest a name using AI
  Future<void> _suggestDiscussionName(Discussion discussion) async {
  final titleColor=Theme.of(context).colorScheme.onSurface;
    final selectedColor =Theme.of(context).colorScheme.primaryContainer;
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Asking AI to suggest a name..."),
            ],
          ),
        );
      },
    );
    
    try {
      List<DiscussionNameSuggestion> response = await _discussionService.getNamesSuggestion(discussion.did);
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      // Show suggestion dialog with mock response
      if (mounted) {
        int selectedIndex = -1; // Track selected suggestion

        showDialog(
          context: context,
          
          builder: (BuildContext context) {
            
            return StatefulBuilder( // Use StatefulBuilder to manage dialog state
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text("Suggested Names"),
                  content: SizedBox(
                    width: MediaQuery.of(context).size.width / 3,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Select one of the AI-suggested names:"),
                        const SizedBox(height: 12),
                        
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: response.length,
                            itemBuilder: (context, index) {
                              final suggestion = response[index];

                              return ListTile(
                                title: Text(
                                  suggestion.name,
                                  style: TextStyle(color: titleColor, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      suggestion.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                selected: selectedIndex == index,
                                selectedTileColor: selectedColor,
                                onTap: () {
                                  setState(() {
                                    selectedIndex = index;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: selectedIndex >= 0 ? () async {
                        final selectedName = response[selectedIndex].name;
                        final selectedDescription = response[selectedIndex].description;
                        Navigator.pop(context);
                        await _updateDiscussion(discussion.did, selectedName, selectedDescription, false);
                        
                      } : null, // Disable if nothing selected
                      child: const Text("Apply Selected Name"),
                    ),
                  ],
                );
              },
            );
          },
        );
      }
    } catch (e) {
      // Close loading dialog if error occurs
      if (mounted) {
        // Close loading dialog if error occurs
        Navigator.of(context).pop();
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to get name suggestion: $e")),
        );
      }
    }
  }

  // Method to rename a discussion
  Future<void> _renameDiscussion(Discussion discussion) async {
    final TextEditingController nameController = TextEditingController(text: discussion.name);
    final TextEditingController descriptionController = TextEditingController(text: discussion.description);
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Rename Discussion"),
          content:  Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "New name"),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: "Description"),
                style: const TextStyle(fontSize: 13), // Smaller text size
                maxLines: 3, // Allow up to 3 lines
                minLines: 1, // Minimum 1 line
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                final String newName = nameController.text.trim();
                final String newDescription = descriptionController.text.trim();
                
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Name cannot be empty"))
                  );
                  return;
                }
                
                Navigator.pop(context);
                await _updateDiscussion(discussion.did, newName, newDescription, false);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
    
    nameController.dispose();
    descriptionController.dispose();
  }

  // Method to delete a discussion
  Future<void> _deleteDiscussion(Discussion discussion) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Delete Discussion"),
          content: const Text("Are you sure you want to delete this discussion? This cannot be undone."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    ) ?? false;
    
    if (confirm) {
      // In a real app, you would delete via API
      await _discussionService.deleteDiscussion(discussion.did);
      // Remove the discussion from the list
      setState(() {
        _discussions.removeWhere((d) => d.did == discussion.did);
      });
    }
  }
  Future<void> _updateDiscussion(int did, String selectedName, String selectedDescription, bool isFavorite ) async {
    // Update the discussion with the selected name and description
    final updateRequest = DiscussionUpdateRequest(
      did: did,
      name: selectedName,
      description: selectedDescription,
      isFavorite:isFavorite
    );
    
    try {
      final discussion = await _discussionService.updateDiscussion(updateRequest);
      
      if (mounted) {
        setState(() {
          // Update local state - find and update the discussion
          final index = _discussions.indexWhere((d) => d.did == did);
          if (index >= 0) {
            _discussions[index] = discussion;
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Discussion updated successfully"))
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update discussion: $error"))
        );
      }
    }

  }

  // toggle the favorite state
  Future<void> _toggleFavorite(Discussion discussion) async {
    final updateRequest = DiscussionUpdateRequest(
      did: discussion.did,
      name: discussion.name,
      description: discussion.description,
      isFavorite: !discussion.isFavorite, 
    );
    
    try {
      final updatedDiscussion = await _discussionService.updateDiscussion(updateRequest);
      
      setState(() {
        // Update discussion in the local list
        final index = _discussions.indexWhere((d) => d.did == discussion.did);
        if (index >= 0) {
          _discussions[index] = updatedDiscussion;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update favorite status: $error"))
        );
      }
    }
  }
}

