// Default settings
const DEFAULTS = {
    trigger: 'right', // 'right' or 'middle'
    padding: 20
};

// Load saved settings
document.addEventListener('DOMContentLoaded', function() {
    chrome.storage.sync.get(DEFAULTS, function(items) {
        const trigger = items.trigger || 'right';
        const padding = typeof items.padding === 'number' ? items.padding : DEFAULTS.padding;
        
        // Set the radio button
        document.getElementById('trigger-' + trigger).checked = true;
        updateSelection(trigger);
        
        // Set the padding input
        const paddingInput = document.getElementById('padding');
        paddingInput.value = padding;
    });
    
    // Add event listeners to radio buttons
    document.querySelectorAll('input[name="trigger"]').forEach(function(radio) {
        radio.addEventListener('change', function() {
            if (this.checked) {
                saveSettings(this.value);
                updateSelection(this.value);
            }
        });
    });
    
    // Add click handlers for the entire option rows
    document.querySelectorAll('.radio-option').forEach(function(option) {
        option.addEventListener('click', function(e) {
            if (e.target.tagName !== 'INPUT') {
                const radio = this.querySelector('input[type="radio"]');
                radio.checked = true;
                saveSettings(radio.value);
                updateSelection(radio.value);
            }
        });
    });
    
    // Add event listener for padding input
    const paddingInput = document.getElementById('padding');
    paddingInput.addEventListener('change', function() {
        let value = parseInt(this.value, 10);
        // Validate range
        if (isNaN(value) || value < 0) value = 0;
        if (value > 500) value = 500;
        this.value = value;
        savePadding(value);
    });
});

function updateSelection(value) {
    document.querySelectorAll('.radio-option').forEach(function(option) {
        option.classList.remove('selected');
    });
    document.getElementById('option-' + value).classList.add('selected');
}

function saveSettings(trigger) {
    chrome.storage.sync.set({ trigger: trigger });
}

function savePadding(padding) {
    chrome.storage.sync.set({ padding: padding });
}
