import React, {useEffect, useState, useRef, useCallback} from 'react';
import {
  StyleSheet,
  Text,
  View,
  FlatList,
  TouchableOpacity,
  Platform,
  StatusBar,
  SafeAreaView,
  NativeModules,
  NativeEventEmitter,
  Animated,
} from 'react-native';

const {KeyEventListener} = NativeModules;
const keyEventEmitter = KeyEventListener
  ? new NativeEventEmitter(KeyEventListener)
  : null;

interface ButtonEvent {
  id: string;
  buttonId: string;
  label: string;
  timestamp: number;
}

const BUTTON_CONFIG: Record<string, {icon: string; color: string; name: string}> = {
  ARROW_UP: {icon: '↑', color: '#4CAF50', name: 'Arrow Up'},
  ARROW_DOWN: {icon: '↓', color: '#4CAF50', name: 'Arrow Down'},
  ARROW_LEFT: {icon: '←', color: '#4CAF50', name: 'Arrow Left'},
  ARROW_RIGHT: {icon: '→', color: '#4CAF50', name: 'Arrow Right'},
  CAMERA: {icon: '📷', color: '#FF9800', name: 'Camera'},
  GEAR: {icon: '⚙️', color: '#2196F3', name: 'Gear'},
  HEART: {icon: '❤️', color: '#E91E63', name: 'Heart / Like'},
  DIAG: {icon: '🔧', color: '#9C27B0', name: 'Diagnostic'},
};

export default function App() {
  const [events, setEvents] = useState<ButtonEvent[]>([]);
  const [isActive, setIsActive] = useState(false);
  const [lastButton, setLastButton] = useState<string | null>(null);
  const [diagInfo, setDiagInfo] = useState<string>('');
  const eventCounter = useRef(0);
  const flashAnim = useRef(new Animated.Value(0)).current;

  const flashButton = useCallback((buttonId: string) => {
    setLastButton(buttonId);
    flashAnim.setValue(1);
    Animated.timing(flashAnim, {
      toValue: 0,
      duration: 1500,
      useNativeDriver: false,
    }).start();
  }, [flashAnim]);

  useEffect(() => {
    if (!keyEventEmitter) return;

    const subscription = keyEventEmitter.addListener('onButtonDetected', (event: any) => {
      eventCounter.current += 1;
      const entry: ButtonEvent = {
        id: `${eventCounter.current}`,
        buttonId: event.buttonId,
        label: event.label,
        timestamp: event.timestamp,
      };

      setEvents(prev => [entry, ...prev].slice(0, 100));
      flashButton(event.buttonId);
    });

    return () => {
      subscription.remove();
      KeyEventListener?.stopListening();
    };
  }, [flashButton]);

  const handleToggle = () => {
    if (!KeyEventListener) return;
    if (isActive) {
      KeyEventListener.stopListening();
      setIsActive(false);
    } else {
      KeyEventListener.startListening();
      setIsActive(true);
    }
  };

  const handleClear = () => {
    setEvents([]);
    setLastButton(null);
    setDiagInfo('');
    eventCounter.current = 0;
  };

  const handleDiagnostics = async () => {
    if (!KeyEventListener?.getDiagnostics) {
      setDiagInfo('getDiagnostics not available');
      return;
    }
    try {
      const d = await KeyEventListener.getDiagnostics();
      const lines = [
        `Window: ${d.windowClass}`,
        `EventWindow: ${d.eventWindowActive ? 'YES' : 'NO'}`,
        `Volume monitor: ${d.volumeMonitorActive ? 'YES' : 'NO'}`,
        `Volume: ${(d.currentVolume * 100).toFixed(0)}%`,
        `Controllers: ${d.connectedControllers}`,
        `Module: ${d.moduleActive ? 'active' : 'inactive'}`,
        `Listeners: ${d.hasListeners ? 'YES' : 'NO'}`,
        `Events: send=${d.sendEventCount} press=${d.pressEventCount} touch=${d.touchEventCount}`,
      ];
      setDiagInfo(lines.join('\n'));
    } catch (e: any) {
      setDiagInfo(`Error: ${e.message}`);
    }
  };

  const formatTime = (ts: number): string => {
    const d = new Date(ts);
    return `${d.getHours().toString().padStart(2, '0')}:${d
      .getMinutes()
      .toString()
      .padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}.${d
      .getMilliseconds()
      .toString()
      .padStart(3, '0')}`;
  };

  const getConfig = (buttonId: string) =>
    BUTTON_CONFIG[buttonId] || {icon: '?', color: '#607D8B', name: buttonId};

  const renderEvent = ({item}: {item: ButtonEvent}) => {
    const config = getConfig(item.buttonId);
    return (
      <View style={[styles.eventRow, {borderLeftColor: config.color}]}>
        <View style={styles.eventHeader}>
          <Text style={styles.eventIcon}>{config.icon}</Text>
          <Text style={[styles.eventName, {color: config.color}]}>{config.name}</Text>
          <Text style={styles.eventTime}>{formatTime(item.timestamp)}</Text>
        </View>
      </View>
    );
  };

  const lastConfig = lastButton ? getConfig(lastButton) : null;
  const flashBg = flashAnim.interpolate({
    inputRange: [0, 1],
    outputRange: ['rgba(0,0,0,0)', lastConfig ? lastConfig.color + '40' : 'rgba(0,0,0,0)'],
  });

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0d0d1a" />
      <View style={styles.header}>
        <Text style={styles.title}>BT Remote Demo</Text>
        <Text style={styles.subtitle}>Beauty-R1 Button Detector | v3.0</Text>
      </View>

      <View style={styles.statusBar}>
        <View style={[styles.statusDot, isActive ? styles.dotActive : styles.dotInactive]} />
        <Text style={styles.statusText}>
          {isActive ? 'Listening...' : 'Tap Start to begin'}
        </Text>
        <Text style={styles.eventCount}>{events.length} presses</Text>
      </View>

      <Animated.View style={[styles.bigDisplay, {backgroundColor: flashBg}]}>
        {lastButton ? (
          <>
            <Text style={styles.bigIcon}>{lastConfig?.icon}</Text>
            <Text style={[styles.bigName, {color: lastConfig?.color}]}>{lastConfig?.name}</Text>
            <Text style={styles.bigLabel}>Button Detected!</Text>
          </>
        ) : (
          <Text style={styles.bigPlaceholder}>
            {isActive ? 'Press a button on your remote...' : 'Start listening to detect buttons'}
          </Text>
        )}
      </Animated.View>

      {isActive && (
        <View style={styles.remoteLayout}>
          <Text style={styles.remoteSectionTitle}>Remote Buttons</Text>
          <View style={styles.remoteGrid}>
            <View style={styles.remoteRow}>
              <View style={styles.remoteSpacer} />
              <ButtonIndicator id="ARROW_UP" lastButton={lastButton} />
              <View style={styles.remoteSpacer} />
            </View>
            <View style={styles.remoteRow}>
              <ButtonIndicator id="ARROW_LEFT" lastButton={lastButton} />
              <View style={styles.remoteCenter} />
              <ButtonIndicator id="ARROW_RIGHT" lastButton={lastButton} />
            </View>
            <View style={styles.remoteRow}>
              <View style={styles.remoteSpacer} />
              <ButtonIndicator id="ARROW_DOWN" lastButton={lastButton} />
              <View style={styles.remoteSpacer} />
            </View>
            <View style={[styles.remoteRow, {marginTop: 8}]}>
              <ButtonIndicator id="GEAR" lastButton={lastButton} />
              <ButtonIndicator id="HEART" lastButton={lastButton} wide />
              <ButtonIndicator id="CAMERA" lastButton={lastButton} />
            </View>
          </View>
        </View>
      )}

      <View style={styles.controls}>
        <TouchableOpacity
          style={[styles.button, isActive ? styles.buttonStop : styles.buttonStart]}
          onPress={handleToggle}>
          <Text style={styles.buttonText}>{isActive ? 'Stop' : 'Start'}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.buttonClear} onPress={handleClear}>
          <Text style={styles.buttonText}>Clear</Text>
        </TouchableOpacity>
        {Platform.OS === 'ios' && (
          <TouchableOpacity style={[styles.buttonClear, {backgroundColor: '#4a148c'}]} onPress={handleDiagnostics}>
            <Text style={styles.buttonText}>Status</Text>
          </TouchableOpacity>
        )}
      </View>

      {diagInfo ? (
        <View style={styles.diagBox}>
          <Text style={styles.diagText}>{diagInfo}</Text>
        </View>
      ) : null}

      <FlatList
        data={events}
        renderItem={renderEvent}
        keyExtractor={item => item.id}
        style={styles.eventList}
        contentContainerStyle={styles.eventListContent}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>
              {isActive ? 'Waiting for button presses...' : 'Press Start to begin'}
            </Text>
          </View>
        }
      />

      <View style={styles.footer}>
        <Text style={styles.footerText}>BT Remote Demo v3.0 | {Platform.OS.toUpperCase()}</Text>
      </View>
    </SafeAreaView>
  );
}

function ButtonIndicator({id, lastButton, wide}: {id: string; lastButton: string | null; wide?: boolean}) {
  const config = BUTTON_CONFIG[id];
  const isActive = lastButton === id;
  return (
    <View
      style={[
        styles.remoteBtn,
        wide && styles.remoteBtnWide,
        isActive && {backgroundColor: config.color + '40', borderColor: config.color},
      ]}>
      <Text style={[styles.remoteBtnIcon, isActive && {opacity: 1}]}>{config.icon}</Text>
      <Text style={[styles.remoteBtnLabel, isActive && {color: config.color}]}>{config.name}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#0d0d1a'},
  header: {paddingHorizontal: 20, paddingTop: 16, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: '#1a1a30'},
  title: {fontSize: 22, fontWeight: 'bold', color: '#e0e0ff'},
  subtitle: {fontSize: 12, color: '#6666aa', marginTop: 2},
  statusBar: {flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingVertical: 8, backgroundColor: '#0a0a18'},
  statusDot: {width: 10, height: 10, borderRadius: 5, marginRight: 8},
  dotActive: {backgroundColor: '#4CAF50'},
  dotInactive: {backgroundColor: '#444'},
  statusText: {flex: 1, color: '#888', fontSize: 13},
  eventCount: {color: '#555', fontSize: 12},
  bigDisplay: {marginHorizontal: 20, marginTop: 12, padding: 20, borderRadius: 16, borderWidth: 1, borderColor: '#1a1a30', alignItems: 'center', minHeight: 100, justifyContent: 'center'},
  bigIcon: {fontSize: 48},
  bigName: {fontSize: 24, fontWeight: 'bold', marginTop: 4},
  bigLabel: {fontSize: 13, color: '#888', marginTop: 4},
  bigPlaceholder: {fontSize: 14, color: '#555', textAlign: 'center'},
  remoteLayout: {marginHorizontal: 20, marginTop: 12, padding: 12, backgroundColor: '#12122a', borderRadius: 12, borderWidth: 1, borderColor: '#1a1a30'},
  remoteSectionTitle: {fontSize: 11, color: '#555', textTransform: 'uppercase', letterSpacing: 1, marginBottom: 8, textAlign: 'center'},
  remoteGrid: {alignItems: 'center'},
  remoteRow: {flexDirection: 'row', justifyContent: 'center', gap: 4},
  remoteSpacer: {width: 52, height: 36},
  remoteCenter: {width: 52, height: 36},
  remoteBtn: {width: 52, height: 36, borderRadius: 6, borderWidth: 1, borderColor: '#2a2a44', backgroundColor: '#16162e', alignItems: 'center', justifyContent: 'center'},
  remoteBtnWide: {width: 80},
  remoteBtnIcon: {fontSize: 14, opacity: 0.4},
  remoteBtnLabel: {fontSize: 7, color: '#555', marginTop: 1},
  controls: {flexDirection: 'row', paddingHorizontal: 20, paddingVertical: 10, gap: 10},
  button: {flex: 1, paddingVertical: 10, borderRadius: 8, alignItems: 'center'},
  buttonStart: {backgroundColor: '#4CAF50'},
  buttonStop: {backgroundColor: '#f44336'},
  buttonClear: {flex: 1, paddingVertical: 10, borderRadius: 8, alignItems: 'center', backgroundColor: '#222244'},
  buttonText: {color: '#fff', fontWeight: 'bold', fontSize: 15},
  eventList: {flex: 1, paddingHorizontal: 20},
  eventListContent: {paddingBottom: 16},
  eventRow: {backgroundColor: '#14142a', borderRadius: 8, padding: 10, marginBottom: 6, borderLeftWidth: 3},
  eventHeader: {flexDirection: 'row', alignItems: 'center', gap: 8},
  eventIcon: {fontSize: 18},
  eventName: {flex: 1, fontWeight: 'bold', fontSize: 15},
  eventTime: {color: '#555', fontSize: 11, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace'},
  emptyState: {paddingVertical: 30, alignItems: 'center'},
  emptyText: {color: '#444', fontSize: 13},
  diagBox: {marginHorizontal: 20, marginVertical: 6, padding: 10, backgroundColor: '#1a0a2e', borderRadius: 8, borderWidth: 1, borderColor: '#4a148c'},
  diagText: {color: '#ce93d8', fontSize: 11, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace', lineHeight: 16},
  footer: {paddingVertical: 6, alignItems: 'center', borderTopWidth: 1, borderTopColor: '#1a1a30'},
  footerText: {color: '#333', fontSize: 10},
});
