# Glyphbase Views

This directory contains different view components for rendering table data.

## KanbanView

Kanban board view with drag-and-drop functionality.

### Usage

```rescript
<KanbanView
  tableId="table-123"
  groupByFieldId="status-field-id"
  rows={allRows}
  fields={tableFields}
  onUpdateRow={(rowId, fieldId, newValue) => {
    // Handle row update
  }}
/>
```

### Features

- ✅ Drag-and-drop cards between columns
- ✅ Groups rows by Select or MultiSelect field
- ✅ Shows card count per column
- ✅ Responsive design
- ✅ Empty column placeholder
- ✅ Primary field as card title
- ✅ Shows first 3 fields as card metadata

### Props

| Prop             | Type                                  | Description                        |
| ---------------- | ------------------------------------- | ---------------------------------- |
| `tableId`        | `string`                              | ID of the table being viewed       |
| `groupByFieldId` | `string`                              | ID of the Select field to group by |
| `rows`           | `array<row>`                          | Array of rows to display           |
| `fields`         | `array<fieldConfig>`                  | Array of field configurations      |
| `onUpdateRow`    | `(string, string, cellValue) => unit` | Callback when a card is moved      |

### Styling

Import the Kanban CSS in your main application:

```javascript
import "./styles/kanban.css";
```

## CalendarView

Calendar view with month/week/day modes for displaying date-based data.

### Usage

```rescript
<CalendarView
  tableId="table-123"
  dateFieldId="due-date-field-id"
  rows={allRows}
  fields={tableFields}
  onEventClick={row => {
    // Handle event click
    Console.log(row.id)
  }}
/>
```

### Features

- ✅ Month view with calendar grid
- ✅ Week/Day view switcher (coming soon)
- ✅ Event cards on calendar days
- ✅ Navigation (previous/next month, today)
- ✅ Today highlighting
- ✅ Up to 3 events per day with "+N more" indicator
- ✅ Event click handler support
- ✅ Primary field as event title
- ✅ Responsive design

### Props

| Prop           | Type                  | Description                             |
| -------------- | --------------------- | --------------------------------------- |
| `tableId`      | `string`              | ID of the table being viewed            |
| `dateFieldId`  | `string`              | ID of the Date field to display events  |
| `rows`         | `array<row>`          | Array of rows to display as events      |
| `fields`       | `array<fieldConfig>`  | Array of field configurations           |
| `onEventClick` | `option<row => unit>` | Optional callback when event is clicked |

### Styling

Import the Calendar CSS in your main application:

```javascript
import "./styles/calendar.css";
```

## GalleryView

Card-based gallery view for displaying visual content with images and metadata.

### Usage

```rescript
<GalleryView
  tableId="table-123"
  coverFieldId={Some("cover-image-field-id")}
  rows={allRows}
  fields={tableFields}
  onCardClick={row => {
    // Handle card click
    Console.log(row.id)
  }}
  layout={Grid}
/>
```

### Features

- ✅ Grid and Masonry layouts
- ✅ Cover image from Attachment or URL field
- ✅ Card-based display with hover effects
- ✅ Click to view full card details in modal
- ✅ Primary field as card title
- ✅ First 3 fields as card metadata
- ✅ Placeholder for cards without images
- ✅ Responsive design with mobile support
- ✅ Full detail modal with all fields

### Props

| Prop           | Type                  | Description                                            |
| -------------- | --------------------- | ------------------------------------------------------ |
| `tableId`      | `string`              | ID of the table being viewed                           |
| `coverFieldId` | `option<string>`      | Optional ID of Attachment or URL field for cover image |
| `rows`         | `array<row>`          | Array of rows to display as cards                      |
| `fields`       | `array<fieldConfig>`  | Array of field configurations                          |
| `onCardClick`  | `option<row => unit>` | Optional callback when card is clicked                 |
| `layout`       | `galleryLayout`       | Grid or Masonry layout (default: Grid)                 |

### Styling

Import the Gallery CSS in your main application:

```javascript
import "./styles/gallery.css";
```

## FormView

Public-facing form view for data entry with validation and success handling.

### Usage

```rescript
<FormView
  tableId="table-123"
  fields={visibleFields}
  config={{
    title: "Contact Form",
    description: Some("Get in touch with us"),
    submitButtonText: "Send Message",
    successMessage: "Thank you! We'll be in touch soon.",
    redirectUrl: Some("https://example.com/thank-you"),
  }}
  onSubmit={async formData => {
    // Handle form submission
    let result = await API.createRow(tableId, formData)
    result
  }}
  showFieldLabels={true}
  showRequiredIndicator={true}
/>
```

### Features

- ✅ Clean, centered form layout with gradient background
- ✅ Support for all common field types (Text, Number, Email, URL, Date,
  Checkbox, Select)
- ✅ Required field validation with asterisk indicators
- ✅ Email and URL format validation
- ✅ Real-time field error messages
- ✅ Form-level error banner
- ✅ Animated success state with checkmark
- ✅ Optional redirect after success
- ✅ Disabled submit button during submission
- ✅ Responsive design with mobile-first approach
- ✅ Accessible form controls

### Props

| Prop                    | Type                                                   | Description                                       |
| ----------------------- | ------------------------------------------------------ | ------------------------------------------------- |
| `tableId`               | `string`                                               | ID of the table to submit data to                 |
| `fields`                | `array<fieldConfig>`                                   | Array of fields to display in form                |
| `config`                | `formConfig`                                           | Form configuration (title, description, messages) |
| `onSubmit`              | `Dict.t<cellValue> => promise<result<string, string>>` | Async callback to handle form submission          |
| `showFieldLabels`       | `bool`                                                 | Show field labels (default: true)                 |
| `showRequiredIndicator` | `bool`                                                 | Show asterisk for required fields (default: true) |

### Styling

Import the Form CSS in your main application:

```javascript
import "./styles/form.css";
```
