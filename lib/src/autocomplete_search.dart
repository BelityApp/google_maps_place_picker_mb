import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:google_maps_place_picker_mb/providers/place_provider.dart';
import 'package:google_maps_place_picker_mb/providers/search_provider.dart';
import 'package:google_maps_place_picker_mb/src/components/prediction_tile.dart';
import 'package:google_maps_place_picker_mb/src/controllers/autocomplete_search_controller.dart';
import 'package:flutter_google_maps_webservices/places.dart';
import 'package:provider/provider.dart';

typedef Row AutoCompleteSearchBuilder(
    BuildContext context, TextEditingController controller);

class AutoCompleteSearch extends StatefulWidget {
  AutoCompleteSearch({
    Key? key,
    required this.sessionToken,
    required this.onPicked,
    required this.appBarKey,
    this.hintText = "Search here",
    this.searchingText = "Searching...",
    this.hidden = false,
    this.height = 40,
    this.autocompleteSortByDistance,
    this.contentPadding = EdgeInsets.zero,
    this.debounceMilliseconds,
    this.onSearchFailed,
    required this.searchBarController,
    this.autocompleteOffset,
    this.autocompleteRadius,
    this.autocompleteLanguage,
    this.autocompleteComponents,
    this.autocompleteTypes,
    this.strictbounds,
    this.region,
    this.initialSearchString,
    this.searchForInitialValue,
    this.autocompleteOnTrailingWhitespace,
    this.builder,
  }) : super(key: key);

  final String? sessionToken;
  final String? hintText;
  final String? searchingText;
  final bool hidden;
  final double height;
  final EdgeInsetsGeometry contentPadding;
  final int? debounceMilliseconds;
  final ValueChanged<Prediction> onPicked;
  final ValueChanged<String>? onSearchFailed;
  final SearchBarController searchBarController;
  final num? autocompleteOffset;
  final num? autocompleteRadius;
  final String? autocompleteLanguage;
  final List<String>? autocompleteTypes;
  final List<Component>? autocompleteComponents;
  final bool? strictbounds;
  final bool? autocompleteSortByDistance;
  final String? region;
  final GlobalKey appBarKey;
  final String? initialSearchString;
  final bool? searchForInitialValue;
  final bool? autocompleteOnTrailingWhitespace;
  final AutoCompleteSearchBuilder? builder;

  @override
  AutoCompleteSearchState createState() => AutoCompleteSearchState();
}

class AutoCompleteSearchState extends State<AutoCompleteSearch> {
  TextEditingController controller = TextEditingController();
  FocusNode focus = FocusNode();
  OverlayEntry? overlayEntry;
  SearchProvider provider = SearchProvider();

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchString != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.text = widget.initialSearchString!;
        if (widget.searchForInitialValue!) {
          _onSearchInputChange();
        }
      });
    }
    controller.addListener(_onSearchInputChange);
    focus.addListener(_onFocusChanged);

    widget.searchBarController.attach(this);
  }

  @override
  void dispose() {
    controller.removeListener(_onSearchInputChange);
    controller.dispose();

    focus.removeListener(_onFocusChanged);
    focus.dispose();
    _clearOverlay();

    super.dispose();
  }

  num computeDistance(
    num lat1,
    num lng1,
    num lat2,
    num lng2,
  ) {
    var x = pi / 180;

    lat1 *= x;
    lng1 *= x;
    lat2 *= x;
    lng2 *= x;

    var distance = 2 *
        asin(sqrt(pow(sin((lat1 - lat2) / 2), 2) +
            cos(lat1) * cos(lat2) * pow(sin((lng1 - lng2) / 2), 2)));

    return distance * 6378137;
  }

  Widget _buildSearchBoxContentWithBuilder() {
    var child = widget.builder!(context, controller);

    assert(child.children.any((element) => element is SearchbarTextField));

    child.children.forEach((t) {
      if (t is SearchbarTextField) {
        assert(t.controller != null,
            "The controller parameter must be passed if the searchBuilder is being used.");
      }
    });

    return child;
  }

  Widget _buildSearchBoxContent({Widget? prefix, Widget? suffix}) {
    return Row(
      children: <Widget>[
        SizedBox(width: 10),
        prefix != null ? prefix : Icon(Icons.search),
        SizedBox(width: 10),
        _buildSearchTextField(),
        suffix != null ? suffix : _buildTextClearIcon(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return !widget.hidden
        ? ChangeNotifierProvider.value(
            value: provider,
            child: RoundedFrame(
              height: widget.height,
              borderColor: colorScheme.primary,
              padding: const EdgeInsets.only(right: 10),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black54
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              elevation: 6.0,
              child: widget.builder == null
                  ? _buildSearchBoxContent()
                  : _buildSearchBoxContentWithBuilder(),
            ),
          )
        : Container();
  }

  Widget _buildSearchTextField() {
    return SearchbarTextField(
      controller: controller,
      contentPadding: widget.contentPadding,
      focus: focus,
      hintText: widget.hintText,
    );
  }

  Widget _buildTextClearIcon() {
    return Selector<SearchProvider, String>(
        selector: (_, provider) => provider.searchTerm,
        builder: (_, data, __) {
          if (data.length > 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                child: Icon(
                  Icons.clear,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
                onTap: () {
                  clearText();
                },
              ),
            );
          } else {
            return SizedBox(width: 10);
          }
        });
  }

  _onSearchInputChange() {
    if (!mounted) return;
    this.provider.searchTerm = controller.text;

    PlaceProvider provider = PlaceProvider.of(context, listen: false);

    if (controller.text.isEmpty) {
      provider.debounceTimer?.cancel();
      _searchPlace(controller.text);
      return;
    }

    if (controller.text.trim() == this.provider.prevSearchTerm.trim()) {
      provider.debounceTimer?.cancel();
      return;
    }

    if (!widget.autocompleteOnTrailingWhitespace! &&
        controller.text.substring(controller.text.length - 1) == " ") {
      provider.debounceTimer?.cancel();
      return;
    }

    if (provider.debounceTimer?.isActive ?? false) {
      provider.debounceTimer!.cancel();
    }

    provider.debounceTimer =
        Timer(Duration(milliseconds: widget.debounceMilliseconds!), () {
      _searchPlace(controller.text.trim());
    });
  }

  _onFocusChanged() {
    PlaceProvider provider = PlaceProvider.of(context, listen: false);
    provider.isSearchBarFocused = focus.hasFocus;
    provider.debounceTimer?.cancel();
    provider.placeSearchingState = SearchingState.Idle;
  }

  _searchPlace(String searchTerm) {
    this.provider.prevSearchTerm = searchTerm;

    _clearOverlay();

    if (searchTerm.length < 1) return;

    _displayOverlay(_buildSearchingOverlay());

    _performAutoCompleteSearch(searchTerm);
  }

  _clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry!.remove();
      overlayEntry = null;
    }
  }

  _displayOverlay(Widget overlayChild) {
    _clearOverlay();

    final RenderBox? appBarRenderBox =
        widget.appBarKey.currentContext!.findRenderObject() as RenderBox?;
    final translation = appBarRenderBox?.getTransformTo(null).getTranslation();
    final Offset offset = translation != null
        ? Offset(translation.x, translation.y)
        : Offset(0.0, 0.0);
    final screenWidth = MediaQuery.of(context).size.width;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarRenderBox!.paintBounds.shift(offset).top +
            appBarRenderBox.size.height,
        left: screenWidth * 0.025,
        right: screenWidth * 0.025,
        child: Material(
          elevation: 4.0,
          child: overlayChild,
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  Widget _buildSearchingOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: <Widget>[
          SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 24),
          Expanded(
            child: Text(
              widget.searchingText ?? "Searching...",
              style: TextStyle(fontSize: 16),
            ),
          )
        ],
      ),
    );
  }

  Future<Widget> _buildPredictionOverlay(List<Prediction> predictions) async {
    PlaceProvider placeProvider = PlaceProvider.of(context, listen: false);
    var map = <Prediction, num>{};
    var sortedPredictions = <Prediction>[];

    if (placeProvider.currentPosition != null &&
        widget.autocompleteSortByDistance == true) {
      for (var i = 0; i < predictions.length; i++) {
        var data = await placeProvider.places.getDetailsByPlaceId(
          predictions[i].placeId!,
          sessionToken: placeProvider.sessionToken,
        );

        map.addAll({
          predictions[i]: computeDistance(
            placeProvider.currentPosition!.latitude,
            placeProvider.currentPosition!.longitude,
            data.result.geometry!.location.lat,
            data.result.geometry!.location.lng,
          )
        });
      }

      var sortedMapEntries = map.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      sortedMapEntries.forEach((element) {
        sortedPredictions.add(element.key);
      });
    }
    return ListBody(
      children: (sortedPredictions.isNotEmpty ? sortedPredictions : predictions)
          .map(
            (p) => PredictionTile(
              prediction: p,
              onTap: (selectedPrediction) {
                resetSearchBar();
                widget.onPicked(selectedPrediction);
              },
            ),
          )
          .toList(),
    );
  }

  _performAutoCompleteSearch(String searchTerm) async {
    PlaceProvider provider = PlaceProvider.of(context, listen: false);

    if (searchTerm.isNotEmpty) {
      final PlacesAutocompleteResponse response =
          await provider.places.autocomplete(
        searchTerm,
        sessionToken: widget.sessionToken,
        location: provider.currentPosition == null
            ? null
            : Location(
                lat: provider.currentPosition!.latitude,
                lng: provider.currentPosition!.longitude),
        offset: widget.autocompleteOffset,
        radius: widget.autocompleteRadius,
        language: widget.autocompleteLanguage,
        types: widget.autocompleteTypes ?? const [],
        components: widget.autocompleteComponents ?? const [],
        strictbounds: widget.strictbounds ?? false,
        region: widget.region,
      );

      if (response.errorMessage?.isNotEmpty == true ||
          response.status == "REQUEST_DENIED") {
        if (widget.onSearchFailed != null) {
          widget.onSearchFailed!(response.status);
        }
        return;
      }

      _displayOverlay(await _buildPredictionOverlay(response.predictions));
    }
  }

  clearText() {
    provider.searchTerm = "";
    controller.clear();
  }

  resetSearchBar() {
    clearText();
    focus.unfocus();
  }

  clearOverlay() {
    _clearOverlay();
  }
}
